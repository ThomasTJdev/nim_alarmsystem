import
  os, strutils, times, asyncdispatch, asyncnet, parsecfg, wiringPiNim

# Config
var dict = loadConfig("config.cfg")
let cfgHostServer = dict.getSectionValue("Socket","HostServer")
let cfgHostPort = parseInt(dict.getSectionValue("Socket","HostPort"))
let cfgSlavePort1 = parseInt dict.getSectionValue("Socket","SlavePort1")


# GPIO
let gpioDoor = toU32(parseInt(dict.getSectionValue("GPIO","Door")))
var bDoorMonitor = false
const
  gpioOn = 1
  gpioOff = 0



#[
    SOCKET CLIENT
    Sending messages to the alarm-main
]#
proc socketClientSend(msg: string) {.async.} =
  ## Sending messages to main controller

  var client = newAsyncSocket()
  try:
    await client.connect(cfgHostServer, Port(cfgHostPort))
    await client.send(msg)
  except:
    discard


# GPIO functions
proc gpioSetup() =
  piPinModeInput(gpioDoor)
  piPullUp(gpioDoor)

proc gpioMonitorDoor() {.async.} =
  var doorSleeper = 0
  while bDoorMonitor:
    if piDigitalRead(gpioDoor) == 1 and doorSleeper == 0:
      await socketClientSend("DOOR:1\r\L")
      doorSleeper = 1
      sleep(1200)
    elif piDigitalRead(gpioDoor) == 0 and doorSleeper == 1:
      doorSleeper = 0
    await sleepAsync(200)

proc terminateGPIO() =
  bDoorMonitor = false
  piDigitalWrite(gpioDoor, gpioOff)



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
  of "XX":
    echo ""
  else:
    discard

proc processClient(client: AsyncSocket) {.async.} =
  ## Process the clients messages.
  ## 
  ## Checks if is alarmed or triggered before parsing the result.

  while true:
    let line = await client.recvLine()
    if line != "":
      asyncCheck socketResponse(line)

    else:
      client.close()
      for i, c in clients:
        if c == client:
          clients.del(i)
          break
      break

proc serveSocket() {.async.} =
  clients = @[]
  var server = newAsyncSocket()
  server.bindAddr(Port(cfgSlavePort1))
  server.listen()

  while true:
    let client = await server.accept()
    clients.add client
    asyncCheck processClient(client)


# Main
proc handler() {.noconv.} =
  echo "Program quitted."
  discard socketClientSend("SLAVE1Quit:Program is quitting\r\L")
  terminateGPIO()
  quit 0

when isMainModule:
  setControlCHook(handler)

  # Checking the RPi
  if piSetup() < 0:
    echo "shit"
    discard socketClientSend("SLAVE1Error:Cannot init the RPi GPIOs\r\L")
    quit 0
  else:
    gpioSetup()
    bDoorMonitor = true
    asyncCheck gpioMonitorDoor()
    discard socketClientSend("SLAVE1On:Slave1 is on\r\L")

  asyncCheck serveSocket()
  runForever()