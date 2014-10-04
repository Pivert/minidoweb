#
#Meteor.publish 'output', Output.find()
# TODO: Find a way to run the following publish commands from Meteor
# Meteor.publish 'actuator', Actuator.find()
# Meteor.publish 'log', Log.find()
# Meteor.publish 'exo', Exo.find()
# Meteor.publish 'exi', Exi.find()

root = exports ? this

printRawPacket = (msg, packet) ->
  msg = msg + (' ' for x in [1..(20 - msg.length)] ).join('')
  toHex = (dec) ->
    if x >= 16 then x.toString(16).toUpperCase() else '0' + x.toString(16)
  now = (new Date).toISOString().split('.')[0]
  pkt = (toHex x for x in packet)
  console.log "#{now} #{msg} #{pkt[0]}<-#{pkt[1]} (#{pkt[2]}) #{pkt[3]} #{pkt[4..].join('|')}"
  
gotZmqObj = (obj) ->
  # First test that this is a valid packet
  if obj.length == 12 and
          obj[MDO.COM] is MDO.CMD.EXO_UPDATE and
          MDO.EXOOFFSET < obj[MDO.DST] and
          obj[MDO.DST] <= MDO.EXOOFFSET + 16
    printRawPacket "EXO_UPDATE", obj
    exo = obj[MDO.DST] - MDO.EXOOFFSET
    exi = ((if obj[MDO.SRC] >= MDO.EXIOFFSET and obj[MDO.SRC] <= MDO.EXIOFFSET + 5 then obj[MDO.SRC] - MDO.EXIOFFSET else 99))
    
    outputStates = obj.slice(4, 4 + obj[MDO.LEN] - 2)
    # Log the packet
    Log.insert
      utctime: new Date()
      exo: exo
      exi: exi
      cmd: obj[MDO.COM]
      outputs: outputStates

    
    # Update the EXO statuses
    Exo.update
      exo: exo
    ,
      utctime: new Date()
      exo: exo
      exi: exi
      cmd: obj[MDO.COM]
      outputs: outputStates 
    ,
      upsert: true

    # For each of the output, check if:
    # - Alredy in the DB
    # - The status has changed

    for output in [1..8]
      lastState = Output.findOne
        exo: exo
        output: output

      # console.log("exo: #{exo} output: #{output} outputState: #{outputStates[output-1]} laststate: #{lastState.state}")
       
      if (not lastState)
      # No record ye.
        Output.insert
          exo: exo
          output: output
          exo: exo
          output: output
          utctime: new Date()
          state: outputStates[output-1]
          lastStateDuration: 0
        
      else if (lastState.state isnt outputStates[output-1])
        console.log("State changed for EXO/Output: #{exo}/#{output}: #{outputStates[output-1]}")
        Output.update
          exo: exo
          output: output
        ,
          $set:
            exo: exo
            output: output
            utctime: new Date()
            state: outputStates[output-1]
            lastStateDuration: (new Date() - lastState.utctime) / 1000
      #else
      #  console.log "Error: lastState.state=#{lastState.state} and outputStates[output-1]=#{outputStates[output-1]}"
    
  else if obj.length >= 5 and obj[MDO.COM] is MDO.CMD.EXICENT
    printRawPacket "EXICENT", obj
  else if obj[MDO.COM] is MDO.CMD.EXI_ECHO_REQUEST
    printRawPacket "EXI_ECHO_REQUEST", obj
  else if obj[MDO.COM] is MDO.CMD.EXI_ECHO_REPLY
    printRawPacket "EXI_ECHO_REPLY", obj
  else if obj[MDO.COM] is MDO.CMD.EXO_ECHO_REQUEST
    printRawPacket "EXO_ECHO_REQUEST", obj
  else if obj[MDO.COM] is MDO.CMD.EXO_ECHO_REPLY
    printRawPacket "EXO_ECHO_REPLY", obj
  else
    printRawPacket "Error - Cannot decode ", obj
  return

Meteor.methods
  exocmd: (cmd) ->
    # Change exo output state
    # cmd = {exo: [1-16], output: [1-8], newstate: [0-255]}

    # Fetch the exo state with all the 8 relay statuses from the DB
    exostate = Exo.findOne({exo: cmd.exo})['outputs']

    # Update the data part with the new state
    exostate[(cmd['output'] - 1)] = cmd['newstate']

    # Let's build a Minido Packet from here.
    minidoexo = cmd.exo + MDO.EXOOFFSET
    mdopkt = [
      0x23,         # Beginig of an MDO packet
      minidoexo,    # Destination ID
      MDWEXIID,     # Source ID
      0x0A,         # LEN: Length of the packet with Lenght octed and checksum
      0x01,         # CMD: Write to exo command
    ].concat(exostate)
    printRawPacket "Sending : ", mdopkt[1..] # Strip the 0x23 to print
    root.zmqPush.send EJSON.stringify(mdopkt)


Meteor.startup ->
  zmq = Meteor.require("zmq")
  socket = zmq.socket("sub")
  socket.subscribe ""
  socket.on "message", Meteor.bindEnvironment((data) ->
    gotZmqObj EJSON.parse(data.slice(1).toString())
  )
  socket.connect "tcp://192.168.232.19:5559"
  console.log "ZMQ subscribed to events"

  root.zmqPush = zmq.socket("push")
  root.zmqPush.connect "tcp://192.168.232.19:5560"
  console.log "ZMQ connected to push channel"

  cur = Output.find()
  
  cur.observeChanges(
    changed: (id, mode) ->
      # Find the related output
      output = Output.findOne _id: id

      # Let's build send learning mode for the exo/output to every EXO
      # mode is in: ['none', 'add', 'remove']
      mode = ['none', 'add', 'remove'].indexOf mode.learning
      for exi in [1..5]
        mdopkt = [
          0x23,                                     # Beginig of an MDO packet
          exi + MDO.EXIOFFSET,                      # Destination ID
          MDWEXIID,                                 # Source ID
          0x06,                                     # LEN: Length of the packet with Lenght octed and checksum
          0x31,                                     # CMD: Write to exo command
          mode,
          output.exo,
          output.output - 1,
          0x00,
        ]
        console.log mdopkt
        printRawPacket "Sending : ", mdopkt[1..] # Strip the 0x23 to print
        root.zmqPush.send EJSON.stringify(mdopkt)
        #
      #Meteor.call 'exilearning',
      #  exo: output.exo
      #  output: output.output
      #  mode: mode.learning
      console.log "Learning Mode changed for " + id + ": " + mode.learning
  )
