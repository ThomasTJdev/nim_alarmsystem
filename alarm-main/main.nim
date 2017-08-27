#[

    Program:    Alarm system for the Raspberry pi
    Version:    0.1
    Author:     Thomas T. Jarløv (https://github.com/ThomasTJdev)
    License:    MIT

    Type:       Main-controller for the RPi

]#

import
  os, strutils, times, jester, asyncdispatch, asyncnet, parsecfg, macros, osproc, db_sqlite, ressources.sqlQuery, ressources.newUser, json, httpclient, cgi, slacklib, wiringPiNim

when not defined(windows):
  import bcrypt # Waiting for dom96 ;-)

# Database
var db: DbConn

# Config
var dict = loadConfig(getAppDir() & "/config.cfg")
let cfgPackageVersion = dict.getSectionValue("Program","Version")

# Database
let 
  cfgDBpath = getAppDir() & "/" & dict.getSectionValue("Database","DBpath")
  cfgDBuser = dict.getSectionValue("Database","DBuser")
  cfgDBpass = dict.getSectionValue("Database","DBpass")
  cfgDB = dict.getSectionValue("Database","DB")

# Socket
let
  cfgHostPort = parseInt dict.getSectionValue("Socket","HostPort")
  cfgSlaveServer1 = dict.getSectionValue("Socket","SlaveServer1")

# Slave camera
let cfgSlaveCamera1 = dict.getSectionValue("Slave1","CameraPort")

# Slack
let cfgSlackOn = parseBool dict.getSectionValue("Slack","SlackOn")

# Jester setting server settings
let cfgWebserverPort = parseInt dict.getSectionValue("Webserver","WebserverPort")
settings:
  port = Port(cfgWebserverPort)

# Alarm
var
  vAlarmCountdownArm = parseInt(dict.getSectionValue("Alarm","CountdownArm"))
  vAlarmCountdownTriggered = parseInt(dict.getSectionValue("Alarm","CountdownTriggered"))
  vAlarmRinging = false
  vAlarmArmed = false
  vAlarmTriggered = false
  vAlarmPwdPeriod = false

# Kioskmode
let cfgKoisk = dict.getSectionValue("Kiosk","KioskMode")
var pKioskmode: Process

# GPIO
var
  bBuzzerBlink = false
  bLedBlink = false
  bPIRmonitor = false
let 
  gpioBuzzer = toU32(parseInt(dict.getSectionValue("GPIO","Buzzer")))
  gpioLEDGreen = toU32(parseInt(dict.getSectionValue("GPIO","LEDGreen")))
  gpioLEDRed = toU32(parseInt(dict.getSectionValue("GPIO","LEDRed")))
  gpioLEDBlue = toU32(parseInt(dict.getSectionValue("GPIO","LEDBlue")))
  gpioPIR = toU32(parseInt(dict.getSectionValue("GPIO","PIR")))
const
  gpioOn = 1
  gpioOff = 0

# Slacklib
import asynchttpserver except Request

slackIncomingWebhookUrl = dict.getSectionValue("Slack","SlackIncomingWebhookUrl")
slackPort = Port(parseInt(dict.getSectionValue("Slack","SlackPort")))

let
  slackChannel = dict.getSectionValue("Slack","SlackChannel")
  slackName = dict.getSectionValue("Slack","SlackName")
  msgFail = slackMsg(slackChannel, slackName, "Failed task", "", "danger", "Alarm Update", "Failed to run the command")
  msgWrongPwd = slackMsg(slackChannel, slackName, "Wrong password", "", "danger", "Alarm Update", "Wrong password entered")
  msgOn = slackMsg(slackChannel, slackName, "Alarms is turned on", "", "good", "Alarm Update", "The controller has been turned on")
  msgOff = slackMsg(slackChannel, slackName, "Alarms is turned off", "", "danger", "Alarm Update", "The controller has been turned off")
  msgArmed = slackMsg(slackChannel, slackName, "Alarms is ARMED", "", "warning", "Alarm Update", "The alarm has been ARMED")
  msgTriggered = slackMsg(slackChannel, slackName, "Alarms is TRIGGERED", "", "warning", "Alarm Update", "The alarm has been TRIGGERED")
  msgTriggeredDoor = slackMsg(slackChannel, slackName, "Alarms is TRIGGERED (door)", "", "warning", "Alarm Update", "The alarm has been TRIGGERED by the door")
  msgTriggeredPIR = slackMsg(slackChannel, slackName, "Alarms is TRIGGERED (PIR)", "", "warning", "Alarm Update", "The alarm has been TRIGGERED by the PIR")
  msgDisarmed = slackMsg(slackChannel, slackName, "Alarms is DISARMED", "", "good", "Alarm Update", "The alarm has been DISARMED")
  msgRinging = slackMsg(slackChannel, slackName, "Alarms is RINGING", "", "danger", "Alarm Update", "The alarm is  RINGING")
  msgSlave1Error = slackMsg(slackChannel, slackName, "Error on SLAVE1", "", "danger", "Alarm Update", "Error on SLAVE1")
  msgSlave1Quit = slackMsg(slackChannel, slackName, "SLAVE1 is quitting", "", "danger", "Alarm Update", "SLAVE1 is quitting")
  msgSlave1On = slackMsg(slackChannel, slackName, "SLAVE1 is on", "", "good", "Alarm Update", "SLAVE1 is on")


# General procs
proc currDate(): string =
  result = format(getLocalTime(getTime()), "dd MMMM yyyy")

proc currTime(): string =
  result = format(getLocalTime(getTime()), "HH:mm:ss")
 
proc alarmStatus(): string =
  if vAlarmRinging:
    result = "Ringing"
  elif vAlarmTriggered:
    result = "Triggered"
  elif vAlarmPwdPeriod:
    result = "Triggered"
  elif vAlarmArmed:
    result = "Armed"
  else:
    result = "Disarmed"


# GPIO functions
proc gpioSetup() =
  piPinModeOutput(gpioLEDGreen)
  piPinModeOutput(gpioLEDRed)
  piPinModeOutput(gpioLEDBlue)
  piPinModeOutput(gpioBuzzer)
  piPinModeInput(gpioPIR)
  
proc gpioBuzzerBlink() {.async.} =
  while bBuzzerBlink:
    piDigitalWrite(gpioBuzzer, gpioOn)
    await sleepAsync(300)
    piDigitalWrite(gpioBuzzer, gpioOff)
    await sleepAsync(800)

proc gpioLedBlink(pin: cint) {.async.} =
  while bLedBlink:
    piDigitalWrite(pin, gpioOn)
    await sleepAsync(300)
    piDigitalWrite(pin, gpioOff)
    await sleepAsync(800)

proc gpioPIRMonitor() {.async.} =
  var countPIR = 0
  while bPIRmonitor and vAlarmArmed == true and vAlarmTriggered == false:
    if piDigitalRead(gpioPIR) == 1:
      inc(countPIR)
      await sleepAsync(1000)
      if piDigitalRead(gpioPIR) == 1:
        asyncCheck slackSend(msgTriggeredPir)
        discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "gpio", "PIR is triggered", currDate(), currTime())
        #vAlarmTriggered = true
      else:
        countPIR = 0
    await sleepAsync(200)

proc terminateGPIOLed() =
  ## Teminates the LED's on the main controller
  
  bLedBlink = false
  piDigitalWrite(gpioLEDRed, gpioOff)
  piDigitalWrite(gpioLEDGreen, gpioOff)
  piDigitalWrite(gpioLEDBlue, gpioOff)

proc terminateGPIOBuzzer() =
  ## Teminates the buzzer on the main controller
  
  bBuzzerBlink = false
  piDigitalWrite(gpioBuzzer, gpioOff)

proc terminateGPIO() =
  ## Terminates all GPIO devices on the main controller

  bPIRmonitor = false
  terminateGPIOLed()
  terminateGPIOBuzzer()  


# Alarm functions
proc alarmRinging() {.async.} =
  ## Activated the ringing when the alarm has been triggered,
  ## and no correct password has been entered

  if cfgSlackOn:
    asyncCheck slackSend(msgRinging)

  discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "state", "Alarm is ringing", currDate(), currTime())
  vAlarmRinging = true
  vAlarmTriggered = false
  vAlarmArmed = false

  terminateGPIO()

  piDigitalWrite(gpioBuzzer, gpioOn)

  bLedBlink = true
  asyncCheck gpioLedBlink(gpioLEDRed)


proc alarmTriggered() {.async.} =
  ## When PIR, door contact e.g. is activated, they activate
  ## alarmTriggered.
  ##
  ## alarmTriggered() will countdown, and if no correct password
  ## is provided, alarmRinging() will be called.

  if vAlarmArmed == true and vAlarmRinging == false and vAlarmPwdPeriod == false:
    vAlarmRinging = false
    vAlarmTriggered = true

    terminateGPIO()

    bBuzzerBlink = true
    asyncCheck gpioBuzzerBlink()
    bLedBlink = true
    asyncCheck gpioLedBlink(gpioLEDBlue)
      
    vAlarmPwdPeriod = true
    discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "state", "Alarm is triggered", currDate(), currTime())


    for i in countup(1, vAlarmCountdownTriggered):
      await sleepAsync(1000)
      if vAlarmArmed == false:
        terminateGPIO()
        break

      if vAlarmArmed and i == vAlarmCountdownTriggered:
        asyncCheck alarmRinging()



proc alarmDisarm(userID: string) =
  ## When correct password is provided, alarmDisarm() is called.

  vAlarmRinging = false
  vAlarmTriggered = false
  vAlarmArmed = false
  vAlarmPwdPeriod = false

  terminateGPIO()

  piDigitalWrite(gpioLEDGreen, gpioOn)

  let userName = getValue(db, sqlSelect("person", ["name"], [""], ["id ="], "", "", ""), userID)
  
  if cfgSlackOn:
    asyncCheck slackSend(msgDisarmed)

    asyncCheck slackSend(slackMsg(slackChannel, slackName, "Alarm: Corret password", "", "good", "Alarm Update", "Corret password entered by " & userName & " at " & format(getLocalTime(getTime()), "dd MMMM yyyy - HH:mm")))

  discard tryInsertID(db, sqlInsert("history", ["type", "user_id", "text", "date", "time"]), "password", userID, userName & ": Correct password is entered", currDate(), currTime())
  discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "state", "Alarm is disarmed", currDate(), currTime())


proc alarmArmed() {.async.} =
  ## When the alarm system is armed, alarmArmed() starts the monitoring.

  if vAlarmRinging == false and vAlarmTriggered == false:
    terminateGPIO()

    bBuzzerBlink = true
    asyncCheck gpioBuzzerBlink()

    piDigitalWrite(gpioLEDGreen, gpioOff)
    bLedBlink = true
    asyncCheck gpioLedBlink(gpioLedBlue)

    if cfgSlackOn:
      asyncCheck slackSend(msgArmed)

    discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "state", "Alarm is armed", currDate(), currTime())

    for i in countup(1, vAlarmCountdownArm):
      if i == 3:
        bBuzzerBlink = false

      if i == (vAlarmCountdownArm - 2):
        bBuzzerBlink = true
        asyncCheck gpioBuzzerBlink()

      await sleepAsync(1000)
    
    if vAlarmRinging == false:
      vAlarmArmed = true
      bBuzzerBlink = false
      bLedBlink = false
      bPIRmonitor = true
      piDigitalWrite(gpioLEDBlue, gpioOff)      
      piDigitalWrite(gpioLEDRed, gpioOn)
      asyncCheck gpioPIRMonitor()

      while vAlarmTriggered == false:
        await sleepAsync(300)
      asyncCheck alarmTriggered()


proc checkPassword(password: string): string =
  ## Checks the entered password against the stored passwords in the database.

  result = ""
  let allPwd = getAllRows(db, sqlSelect("person", ["id", "password", "salt"], [""], [""], "", "", ""))
  for pwd in allPwd:
    if pwd[1] == makePassword(password, pwd[2], pwd[1]):
      result = pwd[0]
      break



#[
    SLACKLIB
    Connected to your slack
]#
proc serverSlackRun(slackReq: asynchttpserver.Request) {.async.} =
  ## Starts the slack app connection
  ## For documentation, see the nimble package 'slacklib'
  
  # No yield inside try/except, therefore workaround with dummy if
  var veri = ""
  try:
    veri = parseJson(slackReq.body)["challenge"].getStr()
  except:  
    discard

  if veri != "":
    # Run the verification process with challenge
    await slackVerifyConnection(slackReq)
  else:
    let slackArg = slackEvent(slackReq, "text")

    case slackEvent(slackReq, "command"):
    of "/arm":
      asyncCheck alarmArmed()
      await slackRespond(slackReq, msgArmed)

    of "/disarm":
      let passwordCheck = checkPassword(slackEvent(slackReq, "text"))
      if passwordCheck != "":
        alarmDisarm(passwordCheck)
        await slackRespond(slackReq, msgDisarmed)
      else:
        await slackRespond(slackReq, msgWrongPwd)
    
    of "/log":
      var limit = "0"
      if slackArg == "":
        limit = "10"
      else:
        limit = slackArg

      let history = getAllRows(db, sqlSelect("history", ["id", "text", "date", "time", "type"], [""], [""], "", "", "ORDER BY id DESC LIMIT " & limit))
      var log = ""
      for item in history:
        log.add(item[0] & " - " & item[2] & " - " & item[3] & " - " & item[1] & "\n")

      let msg = slackMsg(slackChannel, slackName, "nimslack", "Alarm log", "good", "Alarm Update", log)
      await slackRespond(slackReq, msg)

    of "/led":
      case split(slackArg, ":")[0]
      of "off":
        terminateGPIOLed()
        await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "LED's turned off"))
      of "on":
        case split(slackArg, ":")[1]
        of "green":
          piDigitalWrite(gpioLEDGreen, gpioOn)
          await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "LED green turned on"))
        of "blue":
          piDigitalWrite(gpioLEDBlue, gpioOn)
          await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "LED green turned on"))
        of "red":
          piDigitalWrite(gpioLEDRed, gpioOn)
          await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "LED green turned on"))
        else:
          await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "LED could not be identified"))
          discard
      else:
        await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "LED command could not be identified"))
        discard
    
    of "/buzzer":
      terminateGPIOBuzzer()
      if slackArg == "on":
        piDigitalWrite(gpioBuzzer, gpioOn)
        await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "Buzzer turned on"))
      else:
        piDigitalWrite(gpioBuzzer, gpioOff)
        await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "Buzzer turned off"))
    
    of "/pir":
      let passwordCheck = checkPassword(slackEvent(slackReq, "text"))
      if passwordCheck != "":
        bPIRmonitor = false
        await slackRespond(slackReq, slackMsg(slackChannel, slackName, "nimslack", "Alarm Update", "good", "Alarm update", "PIR turned off"))
      else:
        await slackRespond(slackReq, msgWrongPwd)
    else:
      await slackRespond(slackReq, msgFail)
      discard


#[
    JESTER
    Jester webserver and routes
]#
include "tmpl/main.tmpl"

routes:
  get "/":
    if vAlarmRinging:
      resp(genMain(genArmed(true, false, genDisarm())))
    if vAlarmTriggered:
      resp(genMain(genArmed(false, true, genDisarm())))

    resp(genMain(genWelcome()))


  get "/arm":
    if vAlarmRinging:
      resp(genMain(genArmed(true, false, genDisarm())))
    if vAlarmTriggered:
      resp(genMain(genArmed(false, true, genDisarm())))

    resp(genMain(genArm()))


  get "/armed":
    if vAlarmRinging:
      resp(genMain(genArmed(true, false, genDisarm())))
    elif vAlarmTriggered or vAlarmPwdPeriod:
      resp(genMain(genArmed(false, true, genDisarm())))
    elif vAlarmArmed:
      resp(genMain(genArmed(false, false, genDisarm())))
    else:
      asyncCheck alarmArmed()
      resp(genMain(genArmed(false, false, genDisarm())))
    

    #[
    attachment "public/css/style.css"
    await response.sendHeaders()
    await response.send(genMain(genArmed(false, false, "")))

    asyncCheck alarmArmed()
    
    while true:
      # Loop until alarm is triggered, then send the disarm wepage
      if vAlarmTriggered == true:
        await response.send("<div id='alarm-status' data-triggered='true' style='display: none;'></div>")
        await response.send(genDisarm())
        attachment "public/js/js.js"
        response.client.close()
        
        asyncCheck alarmTriggered()
        
        break
      
      await sleepAsync(1000)
    ]#


  get "/disarmManual":
    if vAlarmRinging:
      resp(genMain(genArmed(true, false, genDisarm())))
    if vAlarmTriggered:
      resp(genMain(genArmed(false, true, genDisarm())))

    resp(genMain(genArmed(false, false, genDisarm())))


  post "/disarmconfirm":
    if @"password" == "":
      if cfgSlackOn:
        asyncCheck slackSend(slackMsg(slackChannel, slackName, "Alarm: Wrong password (empty)", "", "danger", "Alarm Update", "Wrong password (empty) entered at " & format(getLocalTime(getTime()), "dd MMMM yyyy - HH:mm")))

      discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "password", "No password entered", currDate(), currTime())
      resp("ERROR")
    
    let passwordCheck = checkPassword(@"password")
    if passwordCheck != "":
        alarmDisarm(passwordCheck)
        resp("OK")
    
    if cfgSlackOn:
      asyncCheck slackSend(slackMsg(slackChannel, slackName, "Alarm: Wrong password", "", "danger", "Alarm Update", "Wrong password entered at " & format(getLocalTime(getTime()), "dd MMMM yyyy - HH:mm")))

    discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "password", "Wrong password", currDate(), currTime())
    resp("ERROR")

  
  get "/camera":
    resp(genMain(genCamera()))


  get "/users":
    resp(genMain(genUser(false)))


  get "/newuserAdd":
    let allPwd = getAllRows(db, sqlSelect("person", ["id", "password", "salt"], [""], ["status ="], "", "", ""), "admin")
    for pwd in allPwd:
      echo pwd[1]
      echo pwd[2]
      if pwd[1] == makePassword(@"adminpassword", pwd[2], pwd[1]):
        let salt = makeSalt()
        let password = makePassword(@"newpassword", salt)
        discard tryInsertID(db, sqlInsert("person", ["name", "password", "salt", "status"]), @"newusername", password, salt, "user")
        discard tryInsertID(db, sqlInsert("history", ["type", "user_id", "text", "date", "time"]), "user", pwd[0], "New user added. Username: " & @"newusername", currDate(), currTime())
        redirect("/")
      else:
        resp(genMain(genUser(true)))


  get "/userdelete":
    cond(@"id" != "")
    let adminStatus = getValue(db, sqlSelect("person", ["status"], [""], ["id ="], "", "", ""), @"id")
    if adminStatus == "admin":
      resp(genMain(genUser(false)))
    else:
      discard tryExec(db, sqlDelete("person", ["id"]), @"id")
      resp(genMain(genUser(false)))



#[
    SOCKET SERVER
    Monitoring the slaves GPIO's feedback
]#
var clients {.threadvar.}: seq[AsyncSocket]

proc socketResponse(data: string) {.async.} =
  ## Parsing and responding on messages sent to the
  ## socket server.
  ##
  ## Result is being parsed split by ':' and used in case.

  case split(data, ":")[0]
  of "DOOR":
    discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "gpio", "Door is triggered", currDate(), currTime())
    if cfgSlackOn:
      asyncCheck slackSend(msgTriggeredDoor)
    vAlarmTriggered = true
  of "SLAVE1Error":
    discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "slave1", "Errors on SLAVE1", currDate(), currTime())
    if cfgSlackOn:
      asyncCheck slackSend(msgSlave1Error)
  of "SLAVE1Quit":
    discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "slave1", "SLAVE1 is quitting", currDate(), currTime())
    if cfgSlackOn:
      asyncCheck slackSend(msgSlave1Quit)
  of "SLAVE1On":
    discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "slave1", "SLAVE1 is on", currDate(), currTime())
    if cfgSlackOn:
      asyncCheck slackSend(msgSlave1On)
  else:
    discard

  if vAlarmTriggered:
    asyncCheck alarmTriggered()

proc processClient(client: AsyncSocket) {.async.} =
  ## Process the clients messages.
  ## 
  ## Checks if is alarmed or triggered before parsing the result.

  while true:
    let line = await client.recvLine()
    if line != "" and vAlarmArmed == true and vAlarmTriggered == false:
      asyncCheck socketResponse(line)
    
    elif line != "" and split(line, ":")[0] == "DOOR":
      discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "gpio", "Door is opened", currDate(), currTime())
    
    elif line != "" and split(line, ":")[0] == "SLAVE1ON":
      discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "slave1", "SLAVE1 is on", currDate(), currTime())
      if cfgSlackOn:
        asyncCheck slackSend(msgSlave1On)
    
    elif line != "" and split(line, ":")[0] == "SLAVE1Quit":
      discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "slave1", "SLAVE1 is quitting", currDate(), currTime())
      if cfgSlackOn:
        asyncCheck slackSend(msgSlave1Quit)
    
    elif line != "" and split(line, ":")[0] == "MSG":
      if cfgSlackOn:
        asyncCheck slackSend(slackMsg(slackChannel, slackName, split(line, ":")[1], "", "good", "Alarm MSG", split(line, ":")[1]))

    else:
      client.close()
      for i, c in clients:
        if c == client:
          clients.del(i)
          break
      break

proc serveSocket() {.async.} =
  ## Starts the socket server

  clients = @[]
  var server = newAsyncSocket()
  server.bindAddr(Port(cfgHostPort))
  server.listen()
  while true:
    let client = await server.accept()
    clients.add client
    asyncCheck processClient(client)





#[
    CTRL+c HANDLER

]#
proc handler() {.noconv.} =
  echo "Program quitted."
  if cfgSlackOn:
    asyncCheck slackSend(msgOff)
  discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "program", "Controller is quitted", currDate(), currTime())
  terminateGPIO()
  terminate(pKioskmode)
  quit 0


#[
    MAIN

]#
when isMainModule:
  setControlCHook(handler)

  # Open DB
  db = open(connection=cfgDBpath, user=cfgDBuser, password=cfgDBpass, database=cfgDB)
  
  # Logging
  discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "program", "Controller is started", currDate(), currTime())

  # Checking the RPi
  if piSetup() < 0:
    echo "Problems with the RPi GPIO. Quitting."
    discard tryInsertID(db, sqlInsert("history", ["type", "text", "date", "time"]), "program", "Problems with the GPIO, quitting.", currDate(), currTime())
    asyncCheck slackSend(slackMsg(slackChannel, slackName, "GPIO problem. Quitting.", "", "danger", "Alarm Update", "Problems with the GPIO. Quitting."))
    quit 0

  # Enabling the GPIO pins
  gpioSetup()
  piDigitalWrite(gpioLEDGreen, gpioOn)

  # Starting kiosk mode
  pKioskmode = startProcess(command=cfgKoisk, options={poUsePath, poEvalCommand, poDemon})
  
  # Start socket server
  asyncCheck serveSocket()
  
  if cfgSlackOn:
    # Start slack server
    asyncCheck slackServer.serve(Port(slackPort), serverSlackRun)
    # Send slack ON msg
    asyncCheck slackSend(msgOn)

  runForever()
  
  db.close()