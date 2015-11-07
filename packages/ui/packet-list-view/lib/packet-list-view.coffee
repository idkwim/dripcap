$ = require('jquery')
_ = require('underscore')
riot = require('riot')
fs = require('fs')
{Component} = require('dripper/component')
remote = require('remote')
Menu = remote.require('menu')
MenuItem = remote.require('menu-item')
dialog = remote.require('dialog')
clipboard = require('clipboard')

class PacketTable
  constructor: (@container, @table) ->
    @sectionSize = 1000
    @sections = []
    @currentSection = null
    @updateSection = _.debounce @update, 100
    @container.scroll => @updateSection()

    exportRawData = =>
      filename = "#{@selctedPacket.interface}-#{@selctedPacket.timestamp.toISOString()}.bin"
      path = dialog.showSaveDialog(remote.getCurrentWindow(), {defaultPath: filename})
      if path?
        fs.writeFileSync path, @selctedPacket.payload

    copyAsJSON = =>
      clipboard.writeText JSON.stringify(@selctedPacket, null, ' ')

    @menu = new Menu()
    @menu.append(new MenuItem(label: 'Export raw data', click: exportRawData))
    @menu.append(new MenuItem(label: 'Copy as JSON', click: copyAsJSON))

  clear: ->
    @sections = []
    @currentSection = null
    @table.find('tr:has(td)').remove()

  autoScroll: ->
    scroll = @container.scrollTop() + @container.height()
    height = @container[0].scrollHeight
    if height - scroll < 64
      @container.scrollTop(height)

  update: ->
    top = @container.scrollTop()
    bottom = @container.height() + top
    begin = Math.floor(top / (16 * @sectionSize))
    end = Math.ceil(bottom / (16 * @sectionSize))

    topPad = 0
    bottomPad = 0

    for s, i in @sections
      if i < begin
        topPad += 16 * s.children().length
        topPad += 16 * s.data('tr').length
        s.hide()
      else if i > end
        bottomPad += 16 * s.children().length
        bottomPad += 16 * s.data('tr').length
        s.hide()
      else
        tr = s.data('tr')
        if tr.length > 0
          for t in tr
            s.append(t)
          s.data('tr', [])
        s.show()

    topPad = Math.max(10, topPad)
    bottomPad = Math.max(10, bottomPad)
    @table.css('padding-top', "#{topPad}px")
    @table.css('padding-bottom', "#{bottomPad}px")

  append: (pkt) ->
    self = @
    tr = $('<tr>')
      .append("<td>#{ pkt.name }</td>")
      .append("<td>#{ pkt.attrs.src }</td>")
      .append("<td>#{ pkt.attrs.dst }</td>")
      .append("<td>#{ pkt.length }</td>")
      .attr('data-filter-rev', '0')
      .data('packet', pkt)
      .on 'click', ->
        self.selectedLine.removeClass('selected') if self.selectedLine?
        self.selectedLine = $(@)
        self.selectedLine.addClass('selected')
      .on 'click', ->
        dripcap.pubsub.pub 'PacketListView:select', $(@).data('packet'), 1
      .on 'contextmenu', (e) =>
        e.preventDefault()
        @selctedPacket = $(e.currentTarget).data('packet')
        @menu.popup(remote.getCurrentWindow())

    process.nextTick =>
      if !@currentSection? || @currentSection.children().length + @currentSection.data('tr').length >= @sectionSize
        @currentSection = $('<tbody>').hide()
        @currentSection.data('tr', [])
        @sections.push @currentSection
        @table.append @currentSection
        @update()

      @updateSection()

      if @currentSection.is(':visible')
        @currentSection.append tr
      else
        @currentSection.data('tr').push tr

class PacketListView
  activate: ->
    @comp = new Component "#{__dirname}/../tag/*.tag"
    dripcap.package.load('main-view').then (pkg) =>
      $ =>
        m = $('<div class="wrapper noscroll" />')
        pkg.root.panel.left('packet-list-view', m)

        n = $('<div class="wrapper" />').attr('tabIndex', '0').appendTo m
        @list = riot.mount n[0], 'packet-list-view',
          items: []

        h = $('<div class="wrapper noscroll" />').css('bottom', 'auto').appendTo m
        riot.mount h[0], 'packet-list-view-header'

        dripcap.session.on 'created', (session) ->
          container = n
          packets = []

          main = $('[riot-tag=packet-list-view] table.main')
          sub = $('[riot-tag=packet-list-view] table.sub').hide()

          mhead = main.find('tr.head').detach()
          shead = sub.find('tr.head').detach()
          main.empty().append(mhead)
          sub.empty().append(shead)
          mainTable = new PacketTable container, main
          subTable = new PacketTable container, sub

          dripcap.pubsub.sub 'PacketFilterView:filter', _.debounce (f) =>
            filterd = []
            for pkt in packets
              filterd.push pkt if f(pkt)

            if packets.length != filterd.length
              @filter = f
              subTable.clear()
              for pkt in filterd
                subTable.append pkt
              sub.show()
              main.hide()
            else
              @filter = null
              sub.hide()
              main.show()
          , 200

          session.on 'packet', (pkt) =>
            packets.push pkt
            mainTable.append pkt
            subTable.append pkt if @filter? && @filter(pkt)
            mainTable.autoScroll()
            subTable.autoScroll()

  updateTheme: (theme) ->
    @comp.updateTheme theme

  deactivate: ->
    @list[0].unmount()
    @comp.destroy()

module.exports = PacketListView
