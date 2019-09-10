---
-- Expy is a simple XP bar replacement addon inspired by more minimal games.
-- @author: Sammy James (aka Pawkette)
-- @copyright: MIT
--
local floor  = math.floor
local unpack = unpack

---
-- Constants
---
local LEVEL_TABLE = {
    70, -- tbc
    80, -- wotlk
    85, -- cata
    90, -- mop
    100, -- wod
    110, -- legion
    120, -- bfa
}

---
-- defines which part of the ui needs update
--
local InvalidationTypes = {
    XP         = 1,
    REST_XP    = 2,
    REST_STATE = 3,
    LEVEL      = 4,
    MODE       = 5,
}

---
-- used to distinguish normal or resting state
--
local PlayerStates = {
    RESTING = 1,
    NORMAL  = 2,
}

---
-- used to distinguish if we're in xp or rep mode
--
local Modes = {
    EXPERIENCE = 1,
    REPUTATION = 2,
}

---
-- these define the colors the addon deals with
--
local Colors = {
    XP         = 1,
    RESTED_XP  = 2,
    RESTING_XP = 3,
    BACKDROP   = 4,
}

---
-- Get the max level for the game
-- @return the max level
--
local function GetMaxLevel()
    local xpac_level = GetExpansionLevel() or 0
    if ( xpac_level > 0 ) then
        return LEVEL_TABLE[ xpac_level ]
    else
        return 60
    end
end

---
-- add commas to a number
-- @return a string value of the number with commas
--
local function PrettyNumber( value )
    -- seems like BreakUpLargeNumbers doesn't work?
    local str_value = tostring( value )
    local value_len = str_value:len()

    if ( value_len <= 3 ) then
        return str_value
    else
        -- credit http://richard.warburton.it
        local left, num, right = string.match( value,'^([^%d]*%d)(%d*)(.-)$' )
        return left .. ( num:reverse():gsub( '(%d%d%d)', '%1,' ):reverse() ) .. right
    end
end

local ADDON_NAME  = ...
local ADDON_TITLE = select( 2, GetAddOnInfo( ADDON_NAME ) )

---
-- Addon
---
local Expy            = LibStub( 'AceAddon-3.0' ):NewAddon( 'Expy', 'AceConsole-3.0', 'AceEvent-3.0' )
Expy.m_CurrentXP      = 0
Expy.m_MaxXP          = 0
Expy.m_DeltaXP        = 0
Expy.m_Level          = 0
Expy.m_XPEnabled      = true
Expy.m_Invalid        = {}
Expy.m_Frame          = nil
Expy.m_Resting        = PlayerStates.NORMAL
Expy.m_RestedXP       = 0
Expy.m_Mode           = Modes.EXPERIENCE
Expy.m_UpdatePending  = false

local LibConfigDialog = LibStub( 'AceConfigDialog-3.0' )
local LibSmooth       = LibStub( 'LibSmoothStatusBar-1.0' )
local LibSM           = LibStub( 'LibSharedMedia-3.0' )
local LibDB           = LibStub( 'AceDB-3.0' )

local options = {
    name      = ADDON_NAME,
    desc      = 'Options for Expy',
    descStyle = 'inline',
    handler   = Expy,
    type      = 'group',
    args = {
        texture = {
            order         = 0,
            name          = 'Texture',
            type          = 'select',
            dialogControl = 'LSM30_Statusbar',
            values        = LibSM:HashTable( 'statusbar' ),
            get           = function() return Expy.db.global.texture end,
            set           = function( _, key ) Expy:SetTexture( key ) end,
        },
        font = {
            order         = 1,
            name          = 'Font',
            type          = 'select',
            dialogControl = 'LSM30_Font',
            values        = LibSM:HashTable( 'font' ),
            get           = function() return Expy.db.global.font end,
            set           = function( _, key ) Expy:SetFont( key ) end,
        },
        height = {
            order = 2,
            name  = 'Height',
            type  = 'range',
            min   = 4,
            max   = 36,
            step  = 1,
            get   = function() return Expy.db.global.height end,
            set   = function( _, key ) Expy:SetHeight( key ) end,
        },
        normal_color = {
            order    = 3,
            name     = 'Normal Color',
            type     = 'color',
            hasAlpha = true,
            get      = function() return Expy:GetColor( Colors.XP ) end,
            set      = function( _, ... ) Expy:SetColor( Colors.XP, ... ) end,
        },
        rested_color = {
            order    = 4,
            name     = 'Rested Color',
            type     = 'color',
            hasAlpha = true,
            get      = function() return Expy:GetColor( Colors.RESTED_XP ) end,
            set      = function( _, ... ) Expy:SetColor( Colors.RESTED_XP, ... ) end,
        },
        resting_color = {
            order    = 5,
            name     = 'Resting Color',
            type     = 'color',
            hasAlpha = true,
            get      = function() return Expy:GetColor( Colors.RESTING_XP ) end,
            set      = function( _, ... ) Expy:SetColor( Colors.RESTING_XP, ... ) end,
        },
        backdrop_color = {
            order    = 6,
            name     = 'Backdrop Color',
            type     = 'color',
            hasAlpha = true,
            get      = function() return Expy:GetColor( Colors.BACKDROP ) end,
            set      = function( _, ... ) Expy:SetColor( Colors.BACKDROP, ... ) end,
        }
    },
}

local OptionsTable = LibStub( 'AceConfig-3.0' ):RegisterOptionsTable( 'Expy', options, {'expy' } )
local DefaultColors = {
    { 0.98, 0.84, 0.09, 1.0  }, -- normal
    { 0.12, 0.69, 0.06, 0.75 }, -- rested
    { 0.09, 0.47, 0.98, 0.75 }, -- resting
    { 0.25, 0.25, 0.25, 0.75 }, -- backdrop
}

---
-- Called when the addon is initialized
--
function Expy:OnInitialize()
    local defaults = {
        profile = {
            texture = LibSM:GetDefault( 'statusbar' ),
            font    = LibSM:GetDefault( 'font' ),
            height  = 8,
            colors  = DefaultColors,
        }
    }

    self.db = LibDB:New( ADDON_NAME .. 'DB', defaults, true )
    LibConfigDialog:AddToBlizOptions( ADDON_NAME, ADDON_TITLE )
end

---
-- Set the texture for the xp bar
-- @param new_texture a texture path
--
function Expy:SetTexture( new_texture )
    self.db.global.texture = new_texture

    local statusbar = LibSM:Fetch( 'statusbar', new_texture )

    self.m_RestBar:SetStatusBarTexture( statusbar )
    self.m_XPBar:SetStatusBarTexture( statusbar )
end

---
-- Set the font for the xp bar
-- @param new_font a font
--
function Expy:SetFont( new_font )
    self.db.global.font = new_font

    local font = LibSM:Fetch( 'font', new_font )

    self.m_Textfield:SetFont( font, 10, nil )
    self.m_LevelField:SetFont( font, 16, nil )
    self.m_Percent:SetFont( font, 10, nil )
end

---
-- Set the height for the status bar
-- @param new_height the new height
--
function Expy:SetHeight( new_height )
    self.db.global.height = new_height

    self.m_Frame:SetHeight( new_height )
end

---
-- Set color information
-- @param color_idx the color to set
-- @param r red component
-- @param g green component
-- @param b blue component
-- @param a alpha component
--
function Expy:SetColor( color_idx, r, g, b, a )
    self.db.global.colors[ color_idx ] = { r, g, b, a }

    self:Invalidate( InvalidationTypes.REST_STATE ) -- slight cheese to avoid duplicate logic
    self.m_XPBar:SetStatusBarColor( self:GetColor( Colors.XP ) )
    self.m_Frame:SetBackdropColor( self:GetColor( Colors.BACKDROP ) )
end

---
-- Get the color for a state
-- @param state the state to get a color for
-- @return r,g,b,a color comonents for a state
--
function Expy:GetColor( color_idx )
    if ( type( self.db.global.colors ) ~= 'table' ) then
        self.db.global.colors = DefaultColors
    end

    return unpack( self.db.global.colors[ color_idx ] )
end

---
-- Called when this addon is enabled
--
function Expy:OnEnable()
    self:RegisterEvent( 'DISABLE_XP_GAIN',       'HandleXPDisabled'       )
    self:RegisterEvent( 'ENABLE_XP_GAIN',        'HandleXPEnabled'        )
    self:RegisterEvent( 'PLAYER_XP_UPDATE',      'HandleXPUpdate'         )
    self:RegisterEvent( 'PLAYER_LEVEL_UP',       'HandleLevelUp'          )
    self:RegisterEvent( 'PLAYER_UPDATE_RESTING', 'HandleRestingUpdate'    )
    self:RegisterEvent( 'UPDATE_EXHAUSTION',     'HandleRestingXPUpdate'  )
    self:RegisterEvent( 'UPDATE_FACTION',        'HandleReputationUpdate' )

    self:InitializeFrame()

    self:HandleRestingUpdate()
    self:HandleLevelUp( nil, UnitLevel( 'player' ) )
    self:HandleXPUpdate()
    self:HandleRestingXPUpdate()
    self:HandleReputationUpdate()
end

---
-- Set up the frame!
--
function Expy:InitializeFrame()
    local statusbar = LibSM:Fetch( 'statusbar', self.db.global.texture or LibSM:GetDefault( 'statusbar' ) )
    local font      = LibSM:Fetch( 'font', self.db.global.font or LibSM:GetDefault( 'font' ) )

    self.m_Frame = CreateFrame( 'Frame', 'Expy', UIParent )
    self.m_Frame.m_Parent = self

    self.m_Frame:SetFrameStrata( 'HIGH' )
    self.m_Frame:SetMovable( false )

    self.m_Frame:ClearAllPoints()
    self.m_Frame:SetPoint( 'BOTTOM', UIParent, 'BOTTOM', 0, 0 )
    self.m_Frame:SetWidth( UIParent:GetWidth() )
    self.m_Frame:SetHeight( self.db.global.height or 8 )

    self.m_Frame:SetBackdrop( {
        bgFile = statusbar,
    } )

    self.m_Frame:SetBackdropColor( self:GetColor( Colors.BACKDROP ) )

    self.m_RestBar = CreateFrame( 'StatusBar', 'Expy.RestBar', self.m_Frame )
    self.m_RestBar:SetStatusBarTexture( statusbar )
    self.m_RestBar:SetStatusBarColor( self:GetColor( Colors.RESTED_XP ) )
    self.m_RestBar:SetPoint( 'TOPLEFT', self.m_Frame, 'TOPLEFT', -1, -1 )
    self.m_RestBar:SetPoint( 'BOTTOMRIGHT', self.m_Frame, 'BOTTOMRIGHT', 1, 1 )
    self.m_RestBar:SetMinMaxValues( 0.0, 1.0 )

    LibSmooth:SmoothBar( self.m_RestBar )

    self.m_XPBar = CreateFrame( 'StatusBar', 'Expy.XPBar', self.m_Frame )
    self.m_XPBar:SetStatusBarTexture( statusbar )
    self.m_XPBar:SetStatusBarColor( self:GetColor( Colors.XP ) )
    self.m_XPBar:SetPoint( 'TOPLEFT', self.m_Frame, 'TOPLEFT', -1, -1 )
    self.m_XPBar:SetPoint( 'BOTTOMRIGHT', self.m_Frame, 'BOTTOMRIGHT', 1, 1 )
    self.m_XPBar:SetMinMaxValues( 0.0, 1.0 )

    LibSmooth:SmoothBar( self.m_XPBar )

    self.m_Textfield = self.m_Frame:CreateFontString( 'Expy.Text', 'OVERLAY' )
    self.m_Textfield:SetShadowOffset( 1, -1 )
    self.m_Textfield:SetTextColor( 1, 1, 1, 1 )
    self.m_Textfield:SetPoint( 'BOTTOMLEFT', self.m_Frame, 'TOPLEFT', 2, 2 )
    self.m_Textfield:SetFont( font, 10, nil )

    self.m_LevelField = self.m_Frame:CreateFontString( 'Expy.Level', 'OVERLAY' )
    self.m_LevelField:SetShadowOffset( 1, -1 )
    self.m_LevelField:SetTextColor( 1, 1, 1, 1 )
    self.m_LevelField:SetPoint( 'BOTTOMLEFT', self.m_Textfield, 'TOPLEFT', 0, 0 )
    self.m_LevelField:SetFont( font, 16, nil )

    self.m_Percent = self.m_Frame:CreateFontString( 'Expy.Percent', 'OVERLAY' )
    self.m_Percent:SetShadowOffset( 1, -1 )
    self.m_Percent:SetTextColor( 1, 1, 1, 1 )
    self.m_Percent:SetPoint( 'LEFT', self.m_Textfield, 'RIGHT', 2, 0 )
    self.m_Percent:SetFont( font, 10, nil )
end

---
-- Called when this addon is disabled
--
function Expy:OnDisable()
    self.m_Frame:Hide()
end

---
-- called to switch between xp and rep mode
-- @param new_mode the mode to be in (Resting or Normal)
--
function Expy:SetMode( new_mode )
    if (new_mode ~= self.m_Mode) then
        self:Invalidate( InvalidationTypes.MODE )
        self.m_Mode = new_mode
    end
end

---
-- This is where we actually determine if we need to update the UI
--
function Expy:OnUpdate()
    if ( self:IsInvalid( InvalidationTypes.LEVEL ) ) then
        local tracked = self:GetTracked()
        if ( tracked ~= nil and type( tracked ) == 'string' ) then
            self.m_LevelField:SetText( tracked )
        else
            self.m_LevelField:SetText( 'No Faction Tracked' )
        end
    end

    if ( self:IsInvalid( InvalidationTypes.XP ) ) then
        local progressText = self:GetProgressText()
        local progressScalar = self:GetProgressScalar()

        if ( progressScalar ~= nil and type( progressScalar ) == 'number' ) then
            self.m_XPBar:SetValue( progressScalar )
            self.m_Percent:SetText( '( ' .. floor( progressScalar * 100.0 ) .. '% )' )
        end

        if ( progressText ~= nil and type( progressText ) == 'string' ) then
            self.m_Textfield:SetText( progressText )
        end

        if ( self.m_RestedXP == nil or self.m_RestedXP == 0 ) then
            self.m_RestBar:SetValue( 0.0 )
        else
            self.m_RestBar:SetValue( ( self.m_CurrentXP + ( self.m_RestedXP or 0 ) ) / self.m_MaxXP )
        end
    end

    if ( self.m_Mode == Modes.EXPERIENCE ) then
        if ( self:IsInvalid( InvalidationTypes.REST_XP ) ) then
            self.m_RestBar:SetValue( ( self.m_CurrentXP + ( self.m_RestedXP or 0 ) ) / self.m_MaxXP )
        end

        if ( self:IsInvalid( InvalidationTypes.REST_STATE ) ) then
            self.m_RestBar:SetStatusBarColor(
                self:GetColor( self.m_Resting == PlayerStates.RESTING and Colors.RESTING_XP or Colors.RESTED_XP ) )
        end
    else
        self.m_RestBar:SetValue( 0.0 )
    end

    -- revert all these to default
    self.m_Invalid = {}
    self.m_Frame:SetScript( 'OnUpdate', nil )
    self.m_UpdatePending = false
end

---
-- bind to 'OnUpdate' and then refresh the ui
--
function Expy:RequestUpdate()
    if ( not self.m_UpdatePending ) then
        self.m_Frame:SetScript( 'OnUpdate', function( frame, _ ) frame.m_Parent:OnUpdate() end )
        self.m_UpdatePending = true
    end
end

---
-- Invalidate a type or types
-- @param types a number or table of numbers to invalidat
--
function Expy:Invalidate( types )
    if ( type( types ) == 'table' ) then
        for i=1,#types,1 do
            if ( not self:IsInvalid( types[ i ] ) ) then
                self.m_Invalid[ types[ i ] ] = true
            end
        end
    elseif ( type( types ) == 'number' ) then
        if ( not self:IsInvalid( types ) ) then
            self.m_Invalid[ types ] = true
        end
    end

    -- register for tick so we can update all at once
    self:RequestUpdate()
end

---
-- Determine if something is invalid
-- @param type the type to check
-- @return if the supplied type is invalid
--
function Expy:IsInvalid( type )
    if ( not type ) then
        local count = 0
        for _,_ in pairs( self.m_Invalid ) do
            count = count + 1
        end
        return count ~= 0
    end

    return self.m_Invalid[ type ] ~= nil
end

---
-- Called when the player disables XP
--
function Expy:HandleXPDisabled()
    self.m_XPEnabled = false

    self:Invalidate( InvalidationTypes.XP )
end

---
-- Called when the player enables XP
--
function Expy:HandleXPEnabled()
    self.m_XPEnabled = true

    self:Invalidate( InvalidationTypes.XP )
end

---
-- Called when a unit's xp changes
--
function Expy:HandleXPUpdate()
    local PreviousXP    = self.m_CurrentXP
    self.m_CurrentXP     = UnitXP( 'player' )
    self.m_MaxXP         = UnitXPMax( 'player' )
    self.m_DeltaXP       = self.m_CurrentXP - PreviousXP

    self:Invalidate( InvalidationTypes.XP )
end

---
-- Called when the player levels up
-- @param level the player's level
--
function Expy:HandleLevelUp( _, level )
    self.m_Level = level
    self.m_MaxXP = UnitXPMax( 'player' )

    if ( self.m_Level == GetMaxLevel() ) then
        self:SetMode( Modes.REPUTATION )
    end
    self:Invalidate( InvalidationTypes.LEVEL )
end

---
-- Called when the player's resting state changes
--
function Expy:HandleRestingUpdate()
    if ( IsResting() ) then
        self.m_Resting = PlayerStates.RESTING
    else
        self.m_Resting = PlayerStates.NORMAL
    end

    self:Invalidate( InvalidationTypes.REST_STATE )
end

---
-- Called when the player's rested xp changes
--
function Expy:HandleRestingXPUpdate()
    self.m_RestedXP = GetXPExhaustion()

    self:Invalidate( InvalidationTypes.REST_XP )
end

---
-- Just refresh everything
--
function Expy:HandleReputationUpdate( _ )
    self:Invalidate( InvalidationTypes.LEVEL )
    self:Invalidate( InvalidationTypes.XP )
end

---
-- Get tracked information (either level or faction)
-- @return a string for what is currently tracked
--
function Expy:GetTracked()
    if ( self.m_Mode == Modes.EXPERIENCE ) then
        return 'Lv ' .. self.m_Level
    elseif ( self.m_Mode == Modes.REPUTATION ) then
        local name, standing, _, _, _ = GetWatchedFactionInfo()
        if ( name ~= nil and standing ~= nil ) then
            return name .. ' (' .. _G[ 'FACTION_STANDING_LABEL' .. standing ] .. ')'
        end
    end

    return nil
end

---
-- Get a scalar for the progress bar
-- @return a number from 0..1
--
function Expy:GetProgressScalar()
    if ( self.m_Mode == Modes.EXPERIENCE ) then
        return self.m_CurrentXP / self.m_MaxXP
    elseif ( self.m_Mode == Modes.REPUTATION ) then
        local _, _, min, max, value = GetWatchedFactionInfo()
        if ( min ~= nil and max ~= nil and value ~= nil ) then
            return (value - min) / (max - min)
        end
    end

    return nil
end

---
-- Get progress text
-- @return a nicely formatted string showing x/y
--
function Expy:GetProgressText()
    if ( self.m_Mode == Modes.EXPERIENCE ) then
        return  PrettyNumber( self.m_CurrentXP ) .. ' / ' .. PrettyNumber( self.m_MaxXP )
    elseif ( self.m_Mode == Modes.REPUTATION ) then
        local _, _, min, max, value = GetWatchedFactionInfo()
        if ( min ~= nil and max ~= nil and value ~= nil ) then
            return PrettyNumber( value - min ) .. ' / ' .. PrettyNumber( max - min )
        end
    end

    return nil
end