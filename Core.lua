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
    60,
    70,
    85,
    90,
    100,
    110,
    120,
}
local MAX_LEVEL     = LEVEL_TABLE[ GetExpansionLevel() ]
local FRAME_HEIGHT  = 8

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

local AddonName = ...
local AddonTitle = select(2, GetAddOnInfo(AddonName))

---
-- Addon
---
local Expy          = LibStub( 'AceAddon-3.0' ):NewAddon( 'Expy', 'AceConsole-3.0', 'AceEvent-3.0' )
Expy._CurrentXP     = 0
Expy._MaxXP         = 0
Expy._DeltaXP       = 0
Expy._Level         = 0
Expy._XPEnabled     = true
Expy._Invalid       = {}
Expy._Frame         = nil
Expy._Resting       = PlayerStates.NORMAL
Expy._RestedXP      = 0
Expy._Mode          = Modes.EXPERIENCE
Expy._UpdatePending = false

local LibConfigDialog = LibStub( 'AceConfigDialog-3.0' )
local LibSmooth       = LibStub( 'LibSmoothStatusBar-1.0' )
local LibSM           = LibStub( 'LibSharedMedia-3.0' )
local LibDB           = LibStub( 'AceDB-3.0' )

local options = {
    name      = AddonName,
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
            get           = function() return Expy._db.texture end,
            set           = function(self, key) Expy:SetTexture( key ) end,
        },
        font = {
            name          = 'Font',
            type          = 'select',
            dialogControl = 'LSM30_Font',
            values        = LibSM:HashTable( 'font' ),
            get           = function() return Expy._db.font end,
            set           = function(self, key) Expy:SetFont( key ) end,
        },
    },
}

local OptionsTable = LibStub( 'AceConfig-3.0' ):RegisterOptionsTable( 'Expy', options, {'expy'} )

local defaults = {
    profile = {
        texture = LibSM:GetDefault( 'statusbar' ),
        font = LibSM:GetDefault( 'font' ),
    }
}

---
-- Called when the addon is initialized
--
function Expy:OnInitialize()
    self._db = LibDB:New( AddonName .. 'DB', defaults ) 
    LibConfigDialog:AddToBlizOptions( AddonName, AddonTitle )
end

function Expy:SetTexture( new_texture )
    self._db.texture = new_texture

    local statusbar = LibSM:Fetch( 'statusbar', new_texture )

    self._RestBar:SetStatusBarTexture( statusbar )
    self._XPBar:SetStatusBarTexture( statusbar )
end

function Expy:SetFont( new_font )
    self._db.font = new_font

    local font = LibSM:Fetch( 'font', new_font )

    self._Textfield:SetFont( font, 10, nil )
    self._LevelField:SetFont( font, 16, nil )
    self._Percent:SetFont( font, 10, nil )
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
    local statusbar = LibSM:Fetch( 'statusbar', self._db.texture or LibSM:GetDefault( 'statusbar' ) )
    local font      = LibSM:Fetch( 'font', self._db.font or LibSM:GetDefault( 'font' ) )

    self._Frame = CreateFrame( 'Frame', 'Expy', UIParent )
    self._Frame._Parent = self

    self._Frame:SetFrameStrata( 'HIGH' )
    self._Frame:SetMovable( false )

    self._Frame:ClearAllPoints()
    self._Frame:SetPoint( 'BOTTOM', UIParent, 'BOTTOM', 0, 0 )
    self._Frame:SetWidth( UIParent:GetWidth() )
    self._Frame:SetHeight( FRAME_HEIGHT )

    self._Frame:SetBackdrop( {
        bgFile = statusbar,
    } )

    self._Frame:SetBackdropColor( 0.25, 0.25, 0.25, 0.75 )

    self._RestBar = CreateFrame( 'StatusBar', 'Expy.RestBar', self._Frame ) 
    self._RestBar:SetStatusBarTexture( statusbar )
    self._RestBar:SetStatusBarColor( 0.12, 0.69, 0.06, 0.75 )
    self._RestBar:SetPoint( 'TOPLEFT', self._Frame, 'TOPLEFT', -1, -1 )
    self._RestBar:SetPoint( 'BOTTOMRIGHT', self._Frame, 'BOTTOMRIGHT', 1, 1 )
    self._RestBar:SetMinMaxValues( 0.0, 1.0 )

    LibSmooth:SmoothBar( self._RestBar )

    self._XPBar = CreateFrame( 'StatusBar', 'Expy.XPBar', self._Frame )
    self._XPBar:SetStatusBarTexture( statusbar )
    self._XPBar:SetStatusBarColor( 0.98, 0.84, 0.09, 1.0 )
    self._XPBar:SetPoint( 'TOPLEFT', self._Frame, 'TOPLEFT', -1, -1 )
    self._XPBar:SetPoint( 'BOTTOMRIGHT', self._Frame, 'BOTTOMRIGHT', 1, 1 )
    self._XPBar:SetMinMaxValues( 0.0, 1.0 )

    LibSmooth:SmoothBar( self._XPBar )

    self._Textfield = self._Frame:CreateFontString( 'Expy.Text', 'OVERLAY' )
    self._Textfield:SetShadowOffset( 1, -1 )
    self._Textfield:SetTextColor( 1, 1, 1, 1 )
    self._Textfield:SetPoint( 'BOTTOMLEFT', self._Frame, 'TOPLEFT', 2, 2 )
    self._Textfield:SetFont( font, 10, nil )

    self._LevelField = self._Frame:CreateFontString( 'Expy.Level', 'OVERLAY' )
    self._LevelField:SetShadowOffset( 1, -1 )
    self._LevelField:SetTextColor( 1, 1, 1, 1 )
    self._LevelField:SetPoint( 'BOTTOMLEFT', self._Textfield, 'TOPLEFT', 0, 0 )
    self._LevelField:SetFont( font, 16, nil )

    self._Percent = self._Frame:CreateFontString( 'Expy.Percent', 'OVERLAY' )
    self._Percent:SetShadowOffset( 1, -1 )
    self._Percent:SetTextColor( 1, 1, 1, 1 )
    self._Percent:SetPoint( 'LEFT', self._Textfield, 'RIGHT', 2, 0 )
    self._Percent:SetFont( font, 10, nil )
end

---
-- Called when this addon is disabled
--
function Expy:OnDisable()
    self._Frame:Hide()
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
    if (new_mode ~= self._Mode) then
        self:Invalidate( InvalidationTypes.MODE )
        self._Mode = new_mode
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
        if ( tracked ~= nil and type(tracked) == 'string' ) then
            self._LevelField:SetText( tracked )
        else 
            self._LevelField:SetText( 'No Faction Tracked' )
        end
    end

    if ( self:IsInvalid( InvalidationTypes.XP ) ) then
        local progressText = self:GetProgressText()
        local progressScalar = self:GetProgressScalar()

        if ( progressScalar ~= nil and type(progressScalar) == 'number' ) then
            self._XPBar:SetValue( progressScalar )
            self._Percent:SetText( '( ' .. floor( progressScalar * 100.0 ) .. '% )' )
        end

        if ( progressText ~= nil and type(progressText) == 'string' ) then
            self._Textfield:SetText( self:GetProgressText() )
        end
    end

    if ( self._Mode == Modes.EXPERIENCE ) then
        if ( self:IsInvalid( InvalidationTypes.REST_XP ) ) then
            self._RestBar:SetValue( ( self._CurrentXP + ( self._RestedXP or 0 ) ) / self._MaxXP )
        end
        
        if ( self:IsInvalid( InvalidationTypes.REST_STATE ) ) then
            if ( self._Resting == PlayerStates.RESTING ) then
                self._RestBar:SetStatusBarColor( 0.09, 0.47, 0.98, 0.75 )
            else
                self._RestBar:SetStatusBarColor( 0.12, 0.69, 0.06, 0.75 )
            end
        end
    else
        self._RestBar:SetValue( 0.0 )
    end

    -- revert all these to default
    self._Invalid = {}
    self._Frame:SetScript( 'OnUpdate', nil )
    self._UpdatePending = false
end

---
-- bind to 'OnUpdate' and then refresh the ui
--
function Expy:RequestUpdate()
    if ( not self._UpdatePending ) then
        self._Frame:SetScript( 'OnUpdate', function( self, _ ) self._Parent:OnUpdate() end )
        self._UpdatePending = true
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
                insert( self._Invalid, types[ i ] )
            end
        end
    elseif ( type( types ) == 'number' ) then
        if ( not self:IsInvalid( types ) ) then
            insert( self._Invalid, types )
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
        return #self._Invalid ~= 0
    end

    for _,v in pairs( self._Invalid ) do
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
    self._XPEnabled = false

    self:Invalidate( InvalidationTypes.XP )
end

---
-- Called when the player enables XP
--
function Expy:HandleXPEnabled()
    self._XPEnabled = true

    self:Invalidate( InvalidationTypes.XP )
end

---
-- Called when a unit's xp changes
--
function Expy:HandleXPUpdate()
    local PreviousXP    = self._CurrentXP

    self._CurrentXP     = UnitXP( 'player' )
    self._DeltaXP       = self._CurrentXP - PreviousXP

    self:Invalidate( InvalidationTypes.XP )
end

---
-- Called when the player levels up
-- 
-- @param level the player's level
--
function Expy:HandleLevelUp( _, level )
    self._Level = level
    self._MaxXP = UnitXPMax( 'player' )

    if ( self._Level == MAX_LEVEL ) then
        self:SetMode( Modes.REPUTATION )
    end
    self:Invalidate( InvalidationTypes.LEVEL )
end

---
-- Called when the player's resting state changes
-- 
function Expy:HandleRestingUpdate()
    if ( IsResting() ) then
        self._Resting = PlayerStates.RESTING
    else
        self._Resting = PlayerStates.NORMAL 
    end

    self:Invalidate( InvalidationTypes.REST_STATE ) 
end

---
-- Called when the player's rested xp changes
--
function Expy:HandleRestingXPUpdate()
    self._RestedXP = GetXPExhaustion()

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
    if ( self._Mode == Modes.EXPERIENCE ) then
        return 'Lv ' .. self._Level
    elseif ( self._Mode == Modes.REPUTATION ) then
        local name, standing, _, _, _ = GetWatchedFactionInfo()
        if ( name ~= nil and standing ~= nil ) then
            return name .. ' (' .. _G[ 'FACTION_STANDING_LABEL' .. standing ] .. ')'
        end
    end

    return nil
end

function Expy:GetProgressScalar()
    if ( self._Mode == Modes.EXPERIENCE ) then
        return self._CurrentXP / self._MaxXP
    elseif ( self._Mode == Modes.REPUTATION ) then
        local _, _, min, max, value = GetWatchedFactionInfo()
        if ( min ~= nil and max ~= nil and value ~= nil ) then
            return (value - min) / (max - min)
        end
    end

    return nil
end

function Expy:GetProgressText()
    if ( self._Mode == Modes.EXPERIENCE ) then
        return  self._CurrentXP .. ' / ' .. self._MaxXP
    elseif ( self._Mode == Modes.REPUTATION ) then
        local _, _, min, max, value = GetWatchedFactionInfo()
        if ( min ~= nil and max ~= nil and value ~= nil ) then
            return (value - min) .. ' / ' .. (max - min)
        end
    end

    return nil
end

