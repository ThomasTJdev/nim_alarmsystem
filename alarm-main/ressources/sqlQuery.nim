import strutils, db_sqlite, times

const cfgDebug = false

proc sqlInsert*(table: string, data: varargs[string]): SqlQuery =
  var fields = "INSERT INTO " & table & " ("
  var vals = ""
  for i, d in data:
    if i > 0:
      fields.add(", ")
      vals.add(", ")
    fields.add(d)
    vals.add('?')
  if cfgDebug:
    echo($getTime() & " " & fields & ") VALUES (" & vals & ")")
  result = sql(fields & ") VALUES (" & vals & ")")

proc sqlUpdate*(table: string, data: varargs[string], where: varargs[string]): SqlQuery =
  var fields = "UPDATE " & table & " SET "
  for i, d in data:
    if i > 0:
      fields.add(", ")
    fields.add(d & " = ?")
  var wes = " WHERE "
  for i, d in where:
    if i > 0: 
      wes.add(" AND ")
    wes.add(d & " = ?")
  if cfgDebug:
    echo($getTime() & " " & fields & wes)
  result = sql(fields & wes)

proc sqlDelete*(table: string, where: varargs[string]): SqlQuery =
  var res = "DELETE FROM " & table
  var wes = " WHERE "
  for i, d in where:
    if i > 0: 
      wes.add(" AND ")
    wes.add(d & " = ?")   
  if cfgDebug:
    echo($getTime() & " " & res & wes)   
  result = sql(res & wes)

proc sqlSelect*(table: string, data: varargs[string], left: varargs[string], whereC: varargs[string], access: string, accessC: string, user: string): SqlQuery =
  var res = "SELECT "
  for i, d in data:
    if i > 0: res.add(", ")
    res.add(d)
  var lef = ""
  for i, d in left:
    if d != "":
      lef.add(" LEFT JOIN ")
      lef.add(d)
  var wes = ""
  for i, d in whereC:
    if d != "" and i == 0:
      wes.add(" WHERE ")
    if i > 0: 
      wes.add(" AND ")
    if d != "":
      wes.add(d & " ?")
  var acc = ""
  if access != "":
    if wes.len == 0:
      acc.add(" WHERE " & accessC & " in ")
      acc.add("(")
    else:
      acc.add(" AND " & accessC & " in (")
    for a in split(access, ","):
      acc.add(a & ",")
    acc = acc[0 .. ^2]
    acc.add(")")
  if cfgDebug:
    echo($getTime() & " " & res & " FROM " & table & lef & wes & acc & " " & $user)
  result = sql(res & " FROM " & table & lef & wes & acc & " " & $user)