module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  _ = env.require 'lodash'
  M = env.matcher
  colors = require 'colornames'
  colorNames = colors.all().filter((v) -> v.css is true).map((v) -> v.name)

  class MilightRgbColorActionHandler extends env.actions.ActionHandler
    constructor: (@provider, @device, @color, @variable) ->
      @_variableManager = @provider.framework.variableManager
      super()

    setup: ->
      @dependOnDevice(@device)
      super()

    executeAction: (simulate) =>
      if @variable?
        @_variableManager.evaluateStringExpression([@variable])
        .then (value) =>
          if value.match(/(#[a-fA-F\d]{6})(.*)/)? or colors(value)?
            @setColor value, simulate
          else
            Promise.reject new Error __("variable value #{value} is not a valid color")
      else
        @setColor @color, simulate

    setColor: (color, simulate) =>
      if simulate
        return Promise.resolve(__("would log set color #{color}"))
      else
        @device.setColor color
        return Promise.resolve(__("set color #{color}"))

  class MilightHueSatActionHandler extends env.actions.ActionHandler
    constructor: (@provider, @device, @color) ->
      @_variableManager = @provider.framework.variableManager
      super()

    setup: ->
      @dependOnDevice(@device)
      super()

    executeAction: (simulate) =>
      @setHueSat @color, simulate

    setHueSat: (color, simulate) =>
      if simulate
        return Promise.resolve(__("would log set hue and saturation to #{color}"))
      else
        @device.setHueSat color
        return Promise.resolve(__("set huesat #{color}"))

  class MilightRgbSaturationActionHandler extends env.actions.ActionHandler
    constructor: (@provider, @device, @saturation) ->
      @_variableManager = @provider.framework.variableManager
      super()

    setup: ->
      @dependOnDevice(@device)
      super()

    executeAction: (simulate) =>
      @setColor @saturation, simulate

    setColor: (saturation, simulate) =>
      if simulate
        return Promise.resolve(__("would log set saturation #{saturation}"))
      else
        @device.changeSaturationTo saturation
        return Promise.resolve(__("set saturation #{saturation}"))

  class MilightRgbColorActionProvider extends env.actions.ActionProvider
    constructor: (@framework) ->
      super()

    parseAction: (input, context) =>
      milightColorDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'MilightRGBWZone', 'MilightBridgeLight', 'MilightFullColorZone'
        ], device.config.class
      ).value()

      # Try to match the input string with: set ->
      m = M(input, context).match(['milight set color '])

      device = null
      color = null
      match = null
      variable = null

      # device name -> color
      m.matchDevice milightColorDevices, (m, d) ->
        # Already had a match with another device?
        if device? and device.id isnt d.id
          context?.addError(""""#{input.trim()}" is ambiguous.""")
          return

        device = d

        m.match [' to '], (m) ->
          m.or [
            # rgb hex like #00FF00
            (m) -> m.match [/(#[a-fA-F\d]{6})(.*)/], (m, s) ->
              color = s.trim()
              match = m.getFullMatch()

            # color name like red
            (m) -> m.match colorNames, (m, s) ->
              color = colors(s)
              match = m.getFullMatch()

            # a variable holding the color value
            (m) -> m.matchVariable (m, s) ->
              variable = s
              match = m.getFullMatch()
          ]

      if match?
        assert device?
        # either variable or color should be set
        assert variable? ^ color?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new MilightRgbColorActionHandler(@, device, color, variable)
        }
        
      # saturation

      device = null
      saturation = null

      m = M(input, context).match(['milight set saturation '])
      m.matchDevice milightColorDevices, (m, d) ->
        if device? and device.id isnt d.id
          context?.addError(""""#{input.trim()}" is ambiguous.""")
          return

        device = d
        m.match [' to '], (m) ->
          m.match [/([0-9]+)(.*)/], (m, s) ->
            saturation = parseInt(s.trim(), 10)
            match = m.getFullMatch()

      if match?
        assert device?
        # either variable or color should be set
        assert saturation?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new MilightRgbSaturationActionHandler(@, device, saturation, variable)
        }
      
      # hue and saturation

      device = null
      saturation = null
      color = null

      m = M(input, context).match(['milight set huesat '])
      m.matchDevice milightColorDevices, (m, d) ->
        if device? and device.id isnt d.id
          context?.addError(""""#{input.trim()}" is ambiguous.""")
          return

        device = d
        m.match [' to '], (m) ->
          m.or [
            # rgb hex like #00FF00
            (m) -> m.match [/(#[a-fA-F\d]{6})(.*)/], (m, s) ->
              color = s.trim()
              match = m.getFullMatch()

            # color name like red
            (m) -> m.match colorNames, (m, s) ->
              color = colors(s)
              match = m.getFullMatch()

            # a variable holding the color value
            (m) -> m.matchVariable (m, s) ->
              variable = s
              match = m.getFullMatch()
          ]

      if match?
        assert device?
        # either variable or color should be set
        assert variable? ^ color?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new MilightHueSatActionHandler(@, device, color, variable)
        }
      else
        return null

  return MilightRgbColorActionProvider
