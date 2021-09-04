#!/usr/bin/env bash
set -e
psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDATABASE" <<-EOSQL
  CREATE USER $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
  CREATE DATABASE $DB_NAME;
  GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
  \connect $DB_NAME $DB_USER
  BEGIN;

  CREATE TABLE IF NOT EXISTS suppliers (
    ogrn bigint unique not null PRIMARY KEY,
    name varchar unique not null,
    short_name varchar not null,
    inn varchar not null,
    kpp varchar not null,
    registered_at TIMESTAMP,
    okpo varchar,
    oktmo_code varchar,
    oktmo_name varchar,
    description varchar ,
    reputation int not null default 0,
    sold_amount float not null default 0.0,
    successful_tenders int not null default 0,
    unsuccessful_tenders int not null default 0,
    is_innovate boolean not null default false,
    CONSTRAINT suppliers_uc UNIQUE (name, inn, kpp)
  );

  CREATE TABLE IF NOT EXISTS unsorted_suppliers (
    id int unique not null GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) PRIMARY KEY,
    name varchar unique,
    short_name varchar,
    type varchar,
    category varchar,
    inn varchar not null,
    added_at timestamp,
    territorial_id int,
    territorial_unit varchar,
    main_okved varchar
  );

  CREATE TABLE IF NOT EXISTS supplier_contacts (
    id int unique not null GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) PRIMARY KEY,
    supplier_id bigint not null,
    first_name varchar,
    middle_name varchar,
    last_name varchar,
    description varchar,
    phone varchar,
    email varchar,
    address varchar,
    CONSTRAINT supplier_fk FOREIGN KEY (supplier_id)
     REFERENCES suppliers(ogrn)
             ON DELETE SET NULL
             ON UPDATE CASCADE
  );

  CREATE TABLE IF NOT EXISTS customers (
    reg_num varchar not null PRIMARY KEY,
    name varchar not null,
    inn varchar not null,
    kpp varchar not null,
    registered_at TIMESTAMP,
    okpo varchar,
    description varchar not null,
    reputation int not null default 0,
    ordered_sum float not null default 0.0,
    successful_tenders int not null default 0,
    unsuccessful_tenders int not null default 0,
    CONSTRAINT customers_uc UNIQUE (name, inn, kpp)
  );

  CREATE TABLE IF NOT EXISTS okpd (
    code varchar PRIMARY KEY,
    name varchar,
    CONSTRAINT okpd_uc UNIQUE (name, code)
  );

  CREATE TABLE IF NOT EXISTS org_codes (
    id int unique not null GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) PRIMARY KEY,
    name varchar,
    code varchar,
    CONSTRAINT org_codes_uc UNIQUE (name, code)
  );

  CREATE TABLE IF NOT EXISTS units (
    name varchar,
    code int not null PRIMARY KEY ,
    national_name varchar,
    international_name varchar,
    national_code varchar,
    international_code varchar,
    CONSTRAINT units_uc UNIQUE (name, code, national_name, international_name, national_code, international_code)
  );

  CREATE TABLE IF NOT EXISTS products (
    guid varchar not null PRIMARY KEY,
    supplier_id bigint not null,
    customer_id varchar not null,
    okpd_code varchar not null,
    okei_code int,
    name varchar not null,
    taxes float not null default 0.0,
    price float not null default 0.0,
    amount float not null default 0.0,
    currency varchar (3) not null default 'RUB',
    description varchar,
    CONSTRAINT okei_products_fk
     FOREIGN KEY(okei_code)
       REFERENCES units(code)
         ON DELETE SET NULL
         ON UPDATE CASCADE,

     CONSTRAINT customer_fk
      FOREIGN KEY(customer_id)
       REFERENCES customers(reg_num)
              ON DELETE SET NULL
              ON UPDATE CASCADE,

      CONSTRAINT supplier_fk
        FOREIGN KEY(supplier_id)
             REFERENCES suppliers(ogrn)
                    ON DELETE SET NULL
                    ON UPDATE CASCADE
  );

  CREATE TABLE IF NOT EXISTS tenders (
    id varchar unique not null PRIMARY KEY,
    reg_num varchar not null,
    resolution int,
    winner bigint,
    price float not null default 0.0,
    currency varchar (3) not null default 'RUB',
    customer varchar not null,
    published_at TIMESTAMP not null,
    url varchar not null,
    CONSTRAINT winning_supplier_fk
     FOREIGN KEY(winner)
       REFERENCES suppliers(ogrn)
         ON DELETE SET NULL
         ON UPDATE CASCADE,
    CONSTRAINT customer_fk
     FOREIGN KEY(customer)
       REFERENCES customers(reg_num)
         ON DELETE SET NULL
         ON UPDATE CASCADE
  );
  CREATE TABLE IF NOT EXISTS tender_suppliers (
    id int unique not null GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) PRIMARY KEY,
    tender_id varchar,
    supplier_id bigint,

    CONSTRAINT tender_tender_fk
     FOREIGN KEY(tender_id)
       REFERENCES tenders(id)
         ON DELETE SET NULL
         ON UPDATE CASCADE,

    CONSTRAINT tender_supplier_fk
     FOREIGN KEY(supplier_id)
       REFERENCES suppliers(ogrn)
         ON DELETE SET NULL
         ON UPDATE CASCADE
  );

  CREATE TABLE IF NOT EXISTS supplier_blacklist (
    id int unique not null GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) PRIMARY KEY,
    reg_num varchar,
    approved_at  timestamp with time zone DEFAULT NULL,
    published_at  timestamp with time zone DEFAULT NULL,
    name varchar,
    short_name varchar,
    create_reason varchar,
    approve_reason varchar,
    supplier_name varchar,
    supplier_type varchar,
    supplier_short_name varchar,
    supplier_inn varchar,
    supplier_kpp varchar,
    tender_id varchar,
    tender_info varchar,
    tender_at timestamp with time zone DEFAULT NULL,
    price float,
    currency varchar,
    state varchar
  );

  CREATE TABLE IF NOT EXISTS innovate_suppliers (
    id int unique not null GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) PRIMARY KEY,
    inn varchar not null unique,
    name varchar not null,
    phone varchar default NULL,
    email varchar default NULL,
    description varchar default NULL,
    reputation int not null default 0,
    successful_tenders int not null default 0,
    unsuccessful_tenders int not null default 0
  );

  INSERT INTO supplier_blacklist (reg_num, approved_at, published_at, name, short_name, create_reason, approve_reason, supplier_name, supplier_type, supplier_short_name, supplier_inn, supplier_kpp, tender_id, tender_info, tender_at, price, currency, state)
  VALUES
    $(cat ../constant_files/blacklist_full.txt)
  ON CONFLICT DO NOTHING
  ;
  INSERT INTO okpd (code, name)
  VALUES
    $(cat ../constant_files/okpd2.txt)
  ON CONFLICT DO NOTHING
  ;
  INSERT INTO org_codes (code, name)
  VALUES
    $(cat ../constant_files/okved2.txt)
  ON CONFLICT DO NOTHING
  ;
  INSERT INTO units (code, name, national_name, international_name, national_code, international_code)
  VALUES
    $(cat ../constant_files/okei2.txt)
  ON CONFLICT DO NOTHING
  ;
  INSERT INTO innovate_suppliers (inn, name, phone, email, description, reputation, successful_tenders, unsuccessful_tenders)
  VALUES
    $(cat ../constant_files/innovative.txt)
  ON CONFLICT DO NOTHING
  ;
  COMMIT;
EOSQL