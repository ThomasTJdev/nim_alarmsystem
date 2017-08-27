import 
  os, strutils, db_sqlite, rdstdin, ressources.newUser, ressources.sqlQuery


# Creating database
echo "Generating database"

var db = open(connection="data/alarm.db", user="alarm", password="", database="alarmdb")

if not db.tryExec(sql"""
create table if not exists person(
  id INTEGER primary key,
  name VARCHAR(100) not null,
  password VARCHAR(100) not null,
  salt varbin(128) not null,
  status VARCHAR(100),
  creation timestamp not null default (STRFTIME('%s', 'now')),
  modified timestamp not null default (STRFTIME('%s', 'now'))
);""", []):
  echo "person table alreay exists"

if not db.tryExec(sql"""
create table if not exists history(
  id INTEGER primary key,
  user_id INTEGER,
  type VARCHAR(100),
  countdown INTEGER,
  text VARCHAR(1000),
  date VARCHAR(100) not null,
  time VARCHAR(100) not null,
  epoch timestamp not null default (STRFTIME('%s', 'now'))
);""", []):
  echo "history table already exists"

echo "Creating admin user"
let iName = readLineFromStdin "Input admin name: "
let iPwd = readLineFromStdin "Input admin password - only numbers (will be saltet and hashed): "

let salt = makeSalt()
let password = makePassword(iPwd, salt)

discard tryInsertID(db, sqlInsert("person", ["name", "password", "salt", "status"]), $iName, password, salt, "admin")

close(db)


# Done
echo ""
echo "Everything is done - you are ready to rock'n'nrool"
echo "Run the controller with ./main"
echo ""
