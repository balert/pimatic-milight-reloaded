module.exports = (env) ->

  assert = env.require 'cassert'
  Promise = env.require 'bluebird'
  _ = env.require 'lodash'
  t = env.require('decl-api').types
  commons = require('pimatic-plugin-commons')(env)
  MilightRGBWZone = require('./milight-rgbwzone')(env)
  Milight = require 'node-milight-promise'

  class MilightFullColorZone extends MilightRGBWZone
    template: 'milight-rgbw'

    constructor: (@config, plugin, lastState) ->
      @debug = plugin.config.debug ? false
      @base = commons.base @, @config.class

      @name = @config.name
      @id = @config.id
      @isVersion6 = true
      @zoneId = @config.zoneId
      @addAttribute 'saturation',
        description: "Saturation value",
        type: t.number
      @actions = _.cloneDeep @actions
      @actions.setHueSat =
        description: 'set only hue and saturation but keep value.'
        params:
          colorCode:
            type: t.string
      @actions.changeSaturationTo =
        description: "Sets the saturation value"
        params:
          hue:
            type: t.number
      @actions.nightMode =
        description: "Enables the night mode"
        params: {}
      @actions.effectMode =
        description: "Set effect mode"
        params:
          mode:
            type: t.number
      @actions.effectNext =
        description: "Switch to next effect mode"
        params: {}
      @actions.effectFaster =
        description: "Increase effect speed"
        params: {}
      @actions.effectSlower =
        description: "Decrease effect speed"
        params: {}

      @_saturation = lastState?.saturation?.value or 0
      super @config, plugin, lastState, true

    destroy: () ->
      @light.close()
      commons.clearAllPeriodicTimers()
      super()

    _onOffCommand: (newState, options = {}) ->
      commands = []
      
      if newState
        commands.push @commands.fullColor.on @zoneId unless options.white
        if newState is @_previousState
          if options.white
            commands.push @commands.fullColor.whiteMode @zoneId
          else
            if options.hue?
              commands.push @commands.fullColor.hue @zoneId, options.hue, true
            if options.saturation?
              commands.push @commands.fullColor.saturation @zoneId, options.saturation

        else
          if options.white ? @_white
            commands.push @commands.fullColor.whiteMode @zoneId
          else
            if options.hue?
              commands.push @commands.fullColor.hue @zoneId, options.hue ? @_hue, true
            if options.saturation?
              commands.push @commands.fullColor.saturation @zoneId, options.saturation

        if options.dimlevel
          commands.push @commands.fullColor.brightness @zoneId, options.dimlevel 
        else
          commands.push @commands.fullColor.brightness @zoneId, @_dimlevel
      else
        commands.push @commands.fullColor.off @zoneId
      @_previousState = newState
      @light.sendCommands commands

    changeSaturationTo: (saturation) ->
      @base.setAttribute "saturation", saturation
      if not @_state
        level = if @_keepDimlevel then @_oldDimlevel else 100
        @_setDimlevel level

      @_onOffCommand on,
        saturation: saturation

    getSaturation: () ->
      Promise.resolve @_saturation

    setHueSat: (color) ->
      @base.debug "huesat change requested to: #{color}"
      rgb = @_hexStringToRgb color
      @base.debug "RGB", rgb
      if _.isEqual rgb, [255,255,255]
        @base.debug "setting white mode"
        @changeWhiteTo true
      else
        hsv = Milight.helper.rgbToHsv.apply Milight.helper, rgb
        @base.debug "setting color to HSV: #{hsv}"
        hsv[0] = (256 + 176 - Math.floor(Number(hsv[0]) / 360.0 * 255.0)) % 256;
        hsv[1] = 100-hsv[1] # invert saturation value
        @base.debug "setting color to HSV: #{hsv}"
        @base.setAttribute "white", false
        @base.setAttribute "hue", hsv[0]
        @base.setAttribute "saturation", hsv[1]

        if @_state
          @_onOffCommand on,
            white: false
            hue: hsv[0]
            saturation: hsv[1]
            dimlevel: @_dimlevel

    setColor: (color) ->
      @base.debug "color change requested to: #{color}"
      rgb = @_hexStringToRgb color
      @base.debug "RGB", rgb
      if _.isEqual rgb, [255,255,255]
        @base.debug "setting white mode"
        @changeWhiteTo true
      else
        hsv = Milight.helper.rgbToHsv.apply Milight.helper, rgb
        @base.debug "setting color to HSV: #{hsv}"
        hsv[0] = (256 + 176 - Math.floor(Number(hsv[0]) / 360.0 * 255.0)) % 256;
        hsv[1] = 100-hsv[1] # invert saturation value
        @base.debug "setting color to HSV: #{hsv}"
        @base.setAttribute "white", false
        @_setDimlevel hsv[2]
        @base.setAttribute "hue", hsv[0]
        @base.setAttribute "saturation", hsv[1]

        if @_state
          @_onOffCommand on,
            white: false
            hue: hsv[0]
            saturation: hsv[1]
            dimlevel: hsv[2]

    nightMode: () ->
      @changeStateTo true
      @light.sendCommands @commands.fullColor.nightMode @zoneId

    effectMode: (mode) ->
      @changeStateTo true
      @light.sendCommands @commands.fullColor.effectMode @zoneId, mode

    effectNext: () ->
      @changeStateTo true
      @light.sendCommands @commands.fullColor.effectModeNext @zoneId

    effectFaster: () ->
      @light.sendCommands @commands.fullColor.effectSpeedUp @zoneId

    effectSlower: () ->
      @light.sendCommands @commands.fullColor.effectSpeedDown @zoneId

    blink: () ->
      @toggle();

    setAction: (action, count, delay) ->
      assert not isNaN count
      assert not isNaN delay
      @base.debug "action requested: #{action} count #{count} delay #{delay}"
      intervalId = null
      count = count *2 if action is "blink"

      command = () =>
        @base.debug "action (#{count})"
        @[action]()
        count -= 1
        if count is 0 and intervalId?
          commons.clearPeriodicTimer intervalId
          @base.debug "finished"

      intervalId = commons.setPeriodicTimer command, delay
