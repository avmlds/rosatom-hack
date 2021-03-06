package processor

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jlaffaye/ftp"
)

const dateLayout = "2006-07-21"

type fileProcessor struct {
	workerID  int
	inputChan <-chan *ftp.Entry
	client    *ftp.ServerConn
	wg        *sync.WaitGroup
	dbChannel chan<- *Tender
}

func (p *fileProcessor) startProcessing() {
	var err error
	var readCloser io.ReadCloser
	var reader = bytes.NewReader(nil)
	var tenderStruct XmlFile

	fmt.Println(p.client.CurrentDir())

	for entry := range p.inputChan {
		fmt.Println("received file: ", entry.Name)
		readCloser, err = p.client.Retr(entry.Name)
		if err != nil {
			fmt.Printf("failed to read file %s due to %v\n", entry.Name, err)
			continue
		}

		buff, err := ioutil.ReadAll(readCloser)
		if err != nil {
			log.Printf("failes to read all to readCloser due to: %v", err)
			continue
		}

		reader.Reset(buff)

		zipReader, err := zip.NewReader(reader, int64(len(buff)))
		if err != nil {
			log.Fatal(err)
		}

		fmt.Printf("file %s unzipped\n", entry.Name)

		// Read all the files from zip archive
		for _, unzippedFile := range zipReader.File {
			fmt.Println("Reading file:", unzippedFile.Name)
			if !strings.HasSuffix(unzippedFile.Name, ".xml") {
				fmt.Println("this is not xml file, skipping it")
				continue
			}

			if unzippedFile.UncompressedSize64 == 0 {
				fmt.Println("this file is empty, skipping it")
				continue
			}

			unzippedFileBytes, err := readZipFile(unzippedFile)
			if err != nil {
				log.Println(err)
				continue
			}

			err = unmarshalPlus(unzippedFileBytes, &tenderStruct)
			if err != nil {
				fmt.Printf("failed to unmarshal contract from file %s due to: %v\n", unzippedFile.Name, err)
				continue
			}

			fmt.Printf("sending tender %s for db update", tenderStruct.Tender.ID)
			p.dbChannel <- &tenderStruct.Tender

		}
	}

	readCloser.Close()
	// канал закрыт, новых файлов нет, завершаем работу
	err = p.client.Quit()
	if err != nil {
		fmt.Printf("worker#%d failed to close ftp server conn: %v\n", p.workerID, err)
	}

	p.wg.Done()

}

func readZipFile(zf *zip.File) ([]byte, error) {
	f, err := zf.Open()
	if err != nil {
		return nil, err
	}

	defer f.Close()

	return ioutil.ReadAll(f)
}

func unmarshalPlus(data []byte, message *XmlFile) error {
	err := xml.Unmarshal(data, &message)
	if err != nil {
		return err
	}

	message.Tender.PublishedAt, _ = time.Parse(dateLayout, message.Tender.PublishDate)

	for i := range message.Tender.Suppliers.Supplier {
		sup := &message.Tender.Suppliers.Supplier[i]
		sup.LegalEntity.EGRULInfo.RegisteredAt, err = time.Parse(dateLayout, sup.LegalEntity.EGRULInfo.RegistrationDate)
		if err != nil {
			log.Printf(
				"failed to parse registration date for contract %v suplier %v, due to: %v",
				message.Tender.ID,
				sup.LegalEntity.EGRULInfo.ShortName,
				err,
			)
		}
	}

	for i := range message.Tender.Products.Product {
		product := &message.Tender.Products.Product[i]
		// если не смогли распарсить, то всё равно 0 будет
		product.VatRUR, _ = strconv.ParseFloat(product.VATRate, 10)
	}

	return nil
}
