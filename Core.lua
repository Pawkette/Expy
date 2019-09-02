---
-- Expy is a simple XP bar replacement addon inspired by more minimal games.
-- author: Sammy James (aka Pawkette)
--
local insert    = table.insert
local remove    = table.remove
local sort      = table.sort
local floor     = math.floor

---
-- Constants
---
local LEVEL_TABLE = 
{
    70,
    85,
    90,
    100,
    110,
    120,
}

local function GetMaxLevel()
    local xpac_level = GetExpansionLevel()
    if ( xpac_level > 0 ) then
        return LEVEL_TABLE[ xpac_level ]
    else
        return 60
    end
end

local FRAME_HEIGHT = 8

local InvalidationTypes = 
{
    XP         = 1,
    REST_XP    = 2,
    REST_STATE = 3,
    LEVEL      = 4,
    MODE       = 5,
}

local PlayerStates = 
{
    RESTING = 1,
    NORMAL  = 2,
}

local Modes =
{
    EXPERIENCE = 1,
    REPUTATION = 2,
}

local ADDON_NAME = ...
local ADDON_TITLE = select( 2, GetAddOnInfo( ADDON_NAME ) )

---
-- Addon
---
local Expy           = LibStub( 'AceAddon-3.0' ):NewAddon( 'Expy', 'AceConsole-3.0', 'AceEvent-3.0' )
Expy.m_CurrentXP     = 0
Expy.m_MaxXP         = 0
Expy.m_DeltaXP       = 0
Expy.m_Level         = 0
Expy.m_XPEnabled     = true
Expy.m_Invalid       = {}
Expy.m_Frame         = nil
Expy.m_Resting       = PlayerStates.NORMAL
Expy.m_RestedXP      = 0
Expy.m_Mode          = Modes.EXPERIENCE
Expy.m_UpdatePending = false

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
            name          = 'Texture',
            type          = 'select',
            dialogControl = 'LSM30_Statusbar',
            values        = LibSM:HashTable( 'statusbar' ),
            get           = function() return Expy.db.global.texture end,
            set           = function(self, key) Expy:SetTexture( key ) end,
        },
        font = {
            name          = 'Font',
            type          = 'select',
            dialogControl = 'LSM30_Font',
            values        = LibSM:HashTable( 'font' ),
            get           = function() return Expy.db.global.font end,
            set           = function(self, key) Expy:SetFont( key ) end,
        },
    },
}

local OptionsTable = LibStub( 'AceConfig-3.0' ):RegisterOptionsTable( 'Expy', options, {'expy'} )

---
-- Called when the addon is initialized
--
function Expy:OnInitialize()
    local defaults = {
        profile = {
            texture = LibSM:GetDefault( 'statusbar' ),
            font = LibSM:GetDefault( 'font' ),
        }
    }

    self.db = LibDB:New( ADDON_NAME .. 'DB', defaults, true ) 
    LibConfigDialog:AddToBlizOptions( ADDON_NAME, ADDON_TITLE )
end

function Expy:SetTexture( new_texture )
    self.db.global.texture = new_texture

    local statusbar = LibSM:Fetch( 'statusbar', new_texture )

    self.m_RestBar:SetStatusBarTexture( statusbar )
    self.m_XPBar:SetStatusBarTexture( statusbar )
end

function Expy:SetFont( new_font )
    self.db.global.font = new_font

    local font = LibSM:Fetch( 'font', new_font )

    self.m_Textfield:SetFont( font, 10, nil )
    self.m_LevelField:SetFont( font, 16, nil )
    self.m_Percent:SetFont( font, 10, nil )
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
    self.m_Frame:SetHeight( FRAME_HEIGHT )

    self.m_Frame:SetBackdrop( {
        bgFile = statusbar,
    } )

    self.m_Frame:SetBackdropColor( 0.25, 0.25, 0.25, 0.75 )

    self.m_RestBar = CreateFrame( 'StatusBar', 'Expy.RestBar', self.m_Frame ) 
    self.m_RestBar:SetStatusBarTexture( statusbar )
    self.m_RestBar:SetStatusBarColor( 0.12, 0.69, 0.06, 0.75 )
    self.m_RestBar:SetPoint( 'TOPLEFT', self.m_Frame, 'TOPLEFT', -1, -1 )
    self.m_RestBar:SetPoint( 'BOTTOMRIGHT', self.m_Frame, 'BOTTOMRIGHT', 1, 1 )
    self.m_RestBar:SetMinMaxValues( 0.0, 1.0 )

    LibSmooth:SmoothBar( self.m_RestBar )

    self.m_XPBar = CreateFrame( 'StatusBar', 'Expy.XPBar', self.m_Frame )
    self.m_XPBar:SetStatusBarTexture( statusbar )
    self.m_XPBar:SetStatusBarColor( 0.98, 0.84, 0.09, 1.0 )
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
-- Called when a user types the slash command /expy
-- 
-- @param anything the user typed with this slash command
--
function Expy:HandleSlashCommand( _ )
end

--- 
-- called to switch between xp and rep mode
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
    if ( not self:IsInvalid() ) then
        return
    end

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
            if ( self.m_Resting == PlayerStates.RESTING ) then
                self.m_RestBar:SetStatusBarColor( 0.09, 0.47, 0.98, 0.75 )
            else
                self.m_RestBar:SetStatusBarColor( 0.12, 0.69, 0.06, 0.75 )
            end
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
    if ( not self._UpdatePending ) then
        self.m_Frame:SetScript( 'OnUpdate', function( self, _ ) self.m_Parent:OnUpdate() end )
        self.m_UpdatePending = true
    end
end

---
-- Invalidate a type or types
--
-- @param types a number or table of numbers to invalidate
function Expy:Invalidate( types )
    if ( type( types ) == 'table' ) then
        for i=1,#types,1 do 
            if ( not self:IsInvalid( types[ i ] ) ) then
                insert( self.m_Invalid, types[ i ] )
            end
        end
    elseif ( type( types ) == 'number' ) then
        if ( not self:IsInvalid( types ) ) then
            insert( self.m_Invalid, types )
        end
    end

    -- register for tick so we can update all at once
    self:RequestUpdate()
end

---
-- Determine if something is invalid
-- 
-- @param type the type to check
function Expy:IsInvalid( type )
    if ( not type ) then 
        return #self.m_Invalid ~= 0
    end

    for _,v in pairs( self.m_Invalid ) do
        if ( v == type ) then
            return true
        end
    end

    return false
end

--
-- Event handling
--

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
-- 
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
function Expy:HandleReputationUpdate(...)
    self:Invalidate( InvalidationTypes.LEVEL )
    self:Invalidate( InvalidationTypes.XP )
end

---
-- getters
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

function Expy:GetProgressText()
    if ( self.m_Mode == Modes.EXPERIENCE ) then
        return  self.m_CurrentXP .. ' / ' .. self.m_MaxXP
    elseif ( self.m_Mode == Modes.REPUTATION ) then
        local _, _, min, max, value = GetWatchedFactionInfo()
        if ( min ~= nil and max ~= nil and value ~= nil ) then
            return (value - min) .. ' / ' .. (max - min)
        end
    end

    return nil
end

