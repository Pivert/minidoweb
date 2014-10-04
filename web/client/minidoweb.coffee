Meteor.subscribe('output')
Meteor.subscribe('actuator')
Meteor.subscribe('log')
Meteor.subscribe('exo')
Meteor.subscribe('exi')

Meteor.startup ->
  root = exports ? this
  root.ShowMenu = (control, e) ->
    # Position the context box
    posx = e.clientX + window.pageXOffset + "px" #Left Position of Mouse Pointer
    posy = e.clientY + window.pageYOffset + "px" #Top Position of Mouse Pointer
    document.getElementById(control).style.position = "absolute"
    document.getElementById(control).style.display = "inline"
    document.getElementById(control).style.left = posx
    document.getElementById(control).style.top = posy

    doc = Output.findOne {_id: Session.get "context" }
    document.getElementById("location").value = if doc.location then doc.location else ''
    document.getElementById("room").value = if doc.room then doc.room else ''
    radiolist = document.getElementsByName('pmode')
    for radio in radiolist
      radio.checked = ( radio.value == doc.learning )

  root.HideMenu = (control) ->
    document.getElementById(control).style.display = "none"

Template.outputs.outputs = ->
  Output.find {},
    sort:
      rank: 1

Template.output.bgcolor = (state) ->
  if state > 20
    "green"
  else
    "gray"

Template.output.duration = (d) ->
  dd = new Date (d * 1000)
  hours = dd.getUTCHours()
  "#{hours}h #{dd.getUTCMinutes()}m #{dd.getUTCSeconds()}s"


Template.output.events =
  "click": (event) ->
    exo   = this.exo
    output= this.output
    Meteor.call('exocmd',
      exo: this.exo
      output: this.output
      newstate: if this.state is 0 then 255 else 0
    )
  "contextmenu": (event) ->
    console.log "contextMenu"
    Session.set "context", this._id
    ShowMenu 'contextMenu',event 


Template.output.displayname = () ->
  if this.location
    room = this.room
    location = this.location
    "#{room}-#{location}"
  else
    exooutput = this.exo
    nroutput = this.output
    "EXO-#{exooutput}.#{nroutput}"

Template.output.exoname = () ->
  exooutput = this.exo
  nroutput = this.output
  "EXO-#{exooutput}.#{nroutput}"

Template.outputs.rendered = ->
  $('#sortable').sortable
    placeholder: "ui-state-highlight"
    stop: (event, ui) ->
      console.log event
      console.log ui
      el = ui.item.get(0)
      before = ui.item.prev().get(0)
      after = ui.item.next().get(0)

      if !before
        newRank = SimpleRationalRanks.beforeFirst(UI.getData(after).rank)
      else if !after
        newRank = SimpleRationalRanks.afterLast(UI.getData(before).rank)
      else
        newRank = SimpleRationalRanks.between(UI.getData(before).rank, UI.getData(after).rank)


      Output.update UI.getData(el)._id,
        $set:
          rank: newRank
  
  $('#sortable').disableSelection()

Template.ctmenu.events =
  "click #validate": ->
    # Read the elements from form and write to DB
    doc = Output.findOne {_id: Session.get "context" }
    location = document.getElementById("location").value
    room = document.getElementById("room").value
    pmode = $('input[name=pmode]:checked').val()
    Output.update {_id: doc._id}, {'$set': {'location': location, 'room': room, 'learning': pmode}}
    HideMenu 'contextMenu'

  "click #cancel": ->
    HideMenu 'contextMenu'

SimpleRationalRanks =
  beforeFirst: (firstrank) -> 
    (firstRank - 1)
  between: (beforeRank, afterRank) ->
    (beforeRank + afterRank) / 2
  afterLast: (lastRank) ->
    (lastRank + 1)
