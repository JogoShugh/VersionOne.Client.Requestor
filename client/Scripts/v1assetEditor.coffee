define ["backbone", "underscore", "toastr", "jquery", "v1json", "jquery.mobile", "jsrender"], (Backbone, _, toastr, $, v1json) ->
  log = (message) ->
    console.log message

  error = (message) ->
    toastr.error message

  success = (message) ->
    toastr.success message

  info = (message) ->
    toastr.info message

  qs = (queryString, key) ->
    key = key.replace(/[*+?^$.\[\]{}()|\\\/]/g, "\\$&") # escape RegEx meta chars
    match = queryString.match(new RegExp("[?&]" + key + "=([^&]+)(&|$)"))
    match and decodeURIComponent(match[1].replace(/\+/g, " "))

  debug = (message) ->
    console.log message if debugEnabled

  $.fn.pressEnter = (fn) ->
    @each ->
      $(this).bind "enterPress", fn
      $(this).keyup (e) ->
        $(this).trigger "enterPress" if e.keyCode is 13

  $("#projectsPage").live "pageinit", ->
    $.mobile.loading('show')
    $('#bodyDiv').css('visibility','visible').hide().fadeIn('slow');
    $.mobile.loading('hide')
  
  class VersionOneAssetEditor
    # Events: assetCreated, assetUpdated, initialized, projectChanged

    constructor: (options) ->          
      continueSettingOptions = =>
        options.whereParamsForProjectScope =
          accept: contentType
          sel: ""
        options.queryOpts = accept: contentType
        options.contentType = contentType      
        for key of options
          @[key] = options[key] 
        @initialize()
      
      contentType = "application/json"
      debugEnabled = options.showDebug
      
      if options.serviceGateway
        $.ajax(options.serviceGateway).done((data) ->
          data = v1json.jsonClean(data)
          options.headers = data
          continueSettingOptions()
        ).fail (ex) ->
          error "Failed to get setup data. The URL used was: " + options.serviceGateway
          log ex
      else
        options.headers = Authorization: "Basic " + btoa(options.versionOneAuth)
        continueSettingOptions()

    debug: (message) ->
      log message if @showDebug

    initialize: ->      
      @requestorName = ""
      @refreshFieldSet "default"
      
      $(".new").click =>
        @newAsset()

      selectFields = []
      @enumFields (key, field) ->        
        # TODO: hard-coded
        selectFields.push key if key isnt "Description" and field.sel isnt false

      @selectFields = selectFields
      $("#list").live "pageinit", @configureListPage

      $("#list").live "pagebeforeshow", =>
        @listFetchIfNotLoaded()
      
      $("#projectsPage").live "pagebeforeshow", =>
        @setTitle "Projects"

      @on "assetCreated", (that, asset) ->
        success "New item created"
        that._normalizeIdWithoutMoment asset
        that._normalizeHrefWithoutMoment asset
        that.listItemPrepend asset

      @on "assetUpdated", (that, asset) ->
        success "Save successful"
        that._normalizeIdWithoutMoment asset
        that._normalizeHrefWithoutMoment asset
        that.listItemReplace asset        

      @configureProjectSearch()
      @toggleNewOrEdit "new"

    refreshFormModel: ->
      @assetFormModel = Backbone.Model.extend({schema: @getFormFields()})

    listFetchIfNotLoaded: ->
      @loadRequests() unless @_listLoaded

    configureProjectSearch: ->
      searchTerm = null
      ajaxRequest = null
      projectSearch = $("#projectSearch")
      projectSearch.pressEnter (e) =>
        target = $(e.currentTarget)
        return if searchTerm is target.val()
        searchTerm = target.val()
        return if searchTerm.length < 4
        $.mobile.loading('show')
        ajaxRequest.abort() if ajaxRequest
        assetName = "Scope"
        url = @getAssetUrl(assetName) + "&" + $.param(
          sel: "Name"
          page: "100,0"
          find: "'" + searchTerm + "'"
          findin: "Name"
        )
        request = @createRequest(url: url)
        projects = $("#projects")
        ajaxRequest = $.ajax(request).done((data) =>
          data = v1json.jsonClean(data)
          ajaxRequest = null
          projects = $("#projects").empty()
          for val in data
            @projectItemAppend val
          projects.listview().listview "refresh"
          $.mobile.loading('hide')
        ).fail(@_ajaxFail)

      @loadProjectIfPassedOnQueryString()

    loadProjectIfPassedOnQueryString: ->
      if window.location.href.indexOf("#list?") > -1
        projectId = qs(window.location.href, "projectId")
        if projectId?
          scopeOid = projectId
          scopeOid = "Scope:" + scopeOid  unless scopeOid.indexOf("Scope:") is 0
          @loadRequests scopeOid, false
      else if window.location.href.indexOf("#detail?") > -1
        projectId = qs(window.location.href, "projectId")
        if projectId?
          scopeOid = projectId
          scopeOid = "Scope:" + scopeOid  unless scopeOid.indexOf("Scope:") is 0
          @setProject scopeOid
          @newAsset()

    configureListPage: ->
      assets = $("#assets")
      assets.empty()
      assets.listview()
      @_listLoaded = false

    _ajaxFail: (ex) ->
      console.log "Error: "
      console.log ex

    setProject: (projectIdref) ->
      @projectIdref = projectIdref
      @refreshFieldSet projectIdref
      #this.configureListPage();
      @_listLoaded = false

    loadRequests: (projectIdref) ->
      @_listLoaded = true
      if not projectIdref?
        projectIdref = @projectIdref
      else
        @setProject projectIdref
      url = @getAssetUrl(@assetName) + "&" + $.param(
        where: "Scope='" + projectIdref + "'"
        sel: "Name,RequestedBy"
        page: "75,0" # TODO: temporary... until real paging support
        sort: "-ChangeDate"
      )
      request = @createRequest(url: url)
      assets = $("#assets")
      assets.empty()
      $.ajax(request).done((data) =>
        data = v1json.jsonClean(data)
        info "Found " + data.length + " requests"
        for item, i in data
          @listAppend item
        assets.listview().listview "refresh"
      ).fail @_ajaxFail
      @changePage "#list"

    refreshFieldSet: (fieldSetName) ->
      if @formFields[fieldSetName]?
        @fieldSetName = fieldSetName
      else
        @fieldSetName = "default"
      @refreshFormModel()

    getFormFields: ->
      return @formFields[@fieldSetName]

    getFormFieldsForSelectQuery: ->
      fields = []
      @enumFields (key) ->
        fields.push key
      fields = fields.join(",")
      fieldsClause = $.param(sel: fields)
      return fieldsClause

    listAppend: (item) ->
      assets = $("#assets")
      templ = @listItemFormat(item)
      assets.append templ

    listItemFormat: (item) ->
      templ = $("<li></li>")
      console.log("The item to append:");
      console.log(item);
      templ.html $("#assetItemTemplate").render(item)
      templ.children(".assetItem").bind "click", (e) =>        
        target = $(e.currentTarget)
        href = target.attr("data-href")
        @editAsset target.attr("data-href")
      return templ

    projectItemAppend: (item) ->
      projects = $("#projects")
      templ = @projectItemFormat(item)
      projects.append templ

    projectItemFormat: (item) ->
      templ = $("<li></li>")
      templ.html $("#projectItemTemplate").render(item)
      templ.children(".projectItem").bind "click", (e) =>
        target = $(e.currentTarget)        
        idref = target.attr("data-idref")
        name = target.attr("data-name")
        @setTitle name
        @setProject idref
        if @projectListClickTarget is "new"
          @newAsset()
        else
          @loadRequests()
      return templ

    setTitle: (title) ->
      $(".title").text ": " + title

    listItemPrepend: (item) ->
      templ = @listItemFormat(item)
      assets = $("#assets")
      assets.prepend templ
      assets.listview().listview "refresh"

    _normalizeIdWithoutMoment: (item) ->
      id = item._links.self.id
      id = id.split(":")
      id.pop() if id.length is 3
      id = id.join(":")
      item._links.self.id = id

    _normalizeHrefWithoutMoment: (item) ->
      href = item._links.self.href
      console.log("The href:");
      console.log(href);
      if href.match(/\D\/\d*?\/\d*$/)
        href = href.split("/")
        href.pop()
        href = href.join("/")
        item._links.self.href = href

    listItemReplace: (item) ->    
      # Thanks to Moments:
      id = item._links.self.id
      templ = @listItemFormat(item)
      assets = $("#assets")
      assets.find("a[data-assetid='" + id + "']").each ->
        listItem = $(this)      
        #var newItem = @listItemFormat(item);
        listItem.closest("li").replaceWith templ
      assets.listview().listview "refresh"

    newAsset: (modelData, href) ->
      @configSelectLists().done =>
        asset = null
        if modelData?        
          asset = new @assetFormModel(modelData)
        else
          asset = new @assetFormModel()
        @asset = asset
        form = new Backbone.Form(model: asset).render()
        @form = form
        @trigger "assetFormCreated", @form
        $("#fields").html form.el
        if modelData?
          @toggleNewOrEdit "edit", href
        else
          @toggleNewOrEdit "new"
        @changePage "#detail"
        @resetForm() unless modelData
        $("#detail").trigger "create"
        
    configSelectLists: ->    
      # Setup the data within select lists
      # TODO: this should not happen on EVERY new click.
      promise = new $.Deferred()
      ajaxRequests = []
      model = new @assetFormModel().schema
      selectLists = []
      for key, value of model
        selectLists.push value if value.options.length < 1 if value.type is "Select"
      that = @	
      for field in selectLists
        do (field) ->  
          assetName = field.editorAttrs["data-assetName"]
          fields = field.formFields
          fields = ["Name"] if not fields? or fields.length is 0
          url = that.service + assetName + "?" + $.param(that.queryOpts) + "&" + $.param(
            sel: fields.join(",")
            sort: "Order"
          )
          request = that.createRequest(
            url: url
            type: "GET"
          )
          ajaxRequest = $.ajax(request).done((data) =>
            data = v1json.jsonClean(data)
            if data.length > 0
              for option in data
                field.options.push
                  val: option._links.self.id
                  label: option.Name
            else
              that.debug "No results for query: " + url
          ).fail(that._ajaxFail)
          ajaxRequests.push ajaxRequest

      return promise if @resolveIfEmpty(promise, ajaxRequests)
      
      @resolveWhenAllDone promise, ajaxRequests
      
      return promise

    resolveIfEmpty: (promise, ajaxRequests) ->
      if ajaxRequests.length < 1
        promise.resolve()
        return true
      return false

    resolveWhenAllDone: (promise, ajaxRequests) ->
      $.when.apply($, ajaxRequests).then ->
        promise.resolve()

    editAsset: (href) ->
      fields = @getFormFields()
      
      url = @host + href + "?" + $.param(@queryOpts)
      fieldsClause = @getFormFieldsForSelectQuery()
      url += "&" + fieldsClause

      asset = @createFetchModel url

      asset.exec().done( (data) =>
        modelData = {}
        model = new @assetFormModel().schema
        links = asset.get('_links')
        for key of model
          value = asset.get(key)
          if value?            
            if fields[key].type == 'Date'
              value = new Date(Date.parse(value))
            modelData[key] = value
          else
            rel = links[key]
            continue if not rel?
            val = links[key]
            if val? and val.length > 0
              val = val[0]
              id = val.idref
              modelData[key] = id
        @newAsset modelData, href
      ).fail @_ajaxFail

    toggleNewOrEdit: (type, href) ->
      save = $("#save")
      saveAndNew = $("#saveAndNew")
      if type is "new"
        save.unbind "click"
        save.bind "click", (evt) =>
          evt.preventDefault()
          @createAsset @assetName, (asset) =>          
            # refresh
            @editAsset asset._links.self.href
        saveAndNew.unbind "click"
        saveAndNew.bind "click", (evt) =>
          evt.preventDefault()
          @createAsset @assetName, =>
            @newAsset()          
            # Hardcoded:
            $("#Name").focus()
      else if type is "edit"
        save.unbind "click"
        save.bind "click", (e) =>
          e.preventDefault()
          @updateAsset href
        saveAndNew.unbind "click"
        saveAndNew.bind "click", (e) =>
          e.preventDefault()
          @updateAsset href, =>
            @newAsset()

    createRequest: (options) ->
      options.headers = @headers  unless @serviceGateway
      return options

    createFetchModel: (url) ->
      options = {}
      options.headers = @headers unless @serviceGateway
      props = 
        url: url
        exec: ->
          return @fetch(options)
        parse: (data) ->
          return v1json.jsonClean(data)


      fetchModel = Backbone.Model.extend(props)

      return new fetchModel()

    createAsset: (assetName, callback) ->
      url = @getAssetUrl(assetName)
      @saveAsset url, "assetCreated", callback

    updateAsset: (href, callback) ->
      url = @host + href + "?" + $.param(@queryOpts)
      @saveAsset url, "assetUpdated", callback

    saveAsset: (url, eventType, callback) ->
      validations = @form.validate()
      if validations?
        error "Please review the form for errors", null,
          positionClass: "toast-bottom-right"
        return
      dto = @createDto()
      payload = v1json.json2xml(dto)
      console.log payload
      request = @createRequest(
        url: url
        type: "POST"
        data: payload
        contentType: "application/xml"
      )
      $.ajax(request).done((data) =>
        data = v1json.jsonClean(data)
        @trigger eventType, @, data
        callback data if callback
      ).fail @_ajaxFail

    createDto: ->
      dto = @form.getValue()

      # TODO: hard-coded for test
      dto._links = Scope:
        idref: @projectIdref

      $("#fields select").each ->
        el = $(this)
        id = el.attr("name")
        val = el.val()
        relationAssetName = el.attr("data-rel")
        if relationAssetName
          dto._links[relationAssetName] = idref: val
          delete dto[id]
      return dto

    getAssetUrl: (assetName) ->
      url = @service + assetName + "?" + $.param(@queryOpts)
      return url

    changePage: (page) ->
      $.mobile.changePage page

    resetForm: ->
      @enumFields (key, field) ->
        $("[name='" + key + "']").each ->
          unless field.type is "select"
            $(this).val ""
            $(this).textinput()    
      '''
      sel = $("[name='Priority']")      
      sel.val "RequestPriority:167"
      sel.selectmenu().selectmenu "refresh"
      '''

    enumFields: (callback) ->
      for key, field of @getFormFields()
        callback key, field

    findField: (fieldName) ->
      fields = [null]
      index = 0
      addField = (key, field) ->
        fields[index++] = field if key is fieldName
      @enumFields addField
      return fields[0]

  debugEnabled = false
  _.extend VersionOneAssetEditor::, Backbone.Events

  return VersionOneAssetEditor