--[[
    Dragon Ball combat mashup for GTA V (Melty / FiveM-style natives)

    Controls
      X            Toggle free flight
      W A S D      Fly / move (air)
      SPACE        Ascend
      LCTRL        Descend
      LSHIFT       Air dash / boost
      R            Charge Ki (hold)
      F            Super Saiyan (requires Ki)
      E            Kamehameha
      RMB          Ki barrage
      Q            Instant Transmission (behind nearest hostile)
      G            Spawn hostile fighters
]]

-- =============================================================================
-- Config
-- =============================================================================

local Config = {
    ki = {
        max = 100.0,
        chargePerSecond = 28.0,
        idleRegenPerSecond = 2.5,
        superSaiyanDrainPerSecond = 4.0,
        transformCost = 35.0,
        kamehamehaCost = 40.0,
        kiBlastCost = 6.0,
        instantTransmissionCost = 18.0,
    },
    flight = {
        cruiseSpeed = 18.0,
        boostSpeed = 42.0,
        verticalSpeed = 16.0,
        boostVertical = 24.0,
    },
    combat = {
        kamehamehaDamage = 220.0,
        kamehamehaRange = 90.0,
        kamehamehaRadius = 3.2,
        kiBlastDamage = 45.0,
        kiBlastRange = 70.0,
        kiBlastCount = 5,
        kiBlastIntervalMs = 90,
        instantTransmissionRange = 80.0,
        spawnCount = 3,
        spawnDistance = 8.0,
    },
    superSaiyan = {
        speedMultiplier = 1.35,
        meleeMultiplier = 2.5,
        damageScale = 1.75,
        auraColor = { r = 255, g = 230, b = 80 },
    },
    keys = {
        flightToggle = 73,   -- X
        chargeKi = 45,       -- R
        transform = 23,      -- F
        kamehameha = 38,     -- E
        kiBlast = 25,        -- Right mouse (aim)
        instantTransmission = 44, -- Q
        spawnEnemies = 47,   -- G
        moveFwd = 32,        -- W
        moveBack = 33,       -- S
        moveLeft = 34,       -- A
        moveRight = 35,      -- D
        ascend = 22,         -- SPACE
        descend = 36,        -- LCTRL
        boost = 21,          -- LSHIFT
    },
    cooldowns = {
        kamehameha = 8000,
        kiBlast = 1200,
        instantTransmission = 6000,
        spawnEnemies = 10000,
        transform = 2500,
    },
    spawnModels = {
        "g_m_y_famca_01",
        "g_m_y_ballasout_01",
        "g_m_y_lost_01",
        "s_m_y_blackops_01",
    },
}

-- =============================================================================
-- State
-- =============================================================================

local State = {
    ki = Config.ki.max,
    flying = false,
    superSaiyan = false,
    charging = false,
    casting = false,
    auraFx = nil,
    lastFrame = 0,
    lastUsed = {
        kamehameha = 0,
        kiBlast = 0,
        instantTransmission = 0,
        spawnEnemies = 0,
        transform = 0,
    },
    spawnedPeds = {},
    fighterGroup = nil,
}

-- =============================================================================
-- Helpers
-- =============================================================================

local function now()
    return GetGameTimer()
end

local function notify(text)
    SetNotificationTextEntry("STRING")
    AddTextComponentString(text)
    DrawNotification(false, false)
end

local function onCooldown(name)
    local elapsed = now() - State.lastUsed[name]
    return elapsed < Config.cooldowns[name]
end

local function remainingCooldown(name)
    local left = Config.cooldowns[name] - (now() - State.lastUsed[name])
    return math.max(0, math.ceil(left / 1000.0))
end

local function markUsed(name)
    State.lastUsed[name] = now()
end

local function spendKi(amount)
    if State.ki < amount then
        return false
    end
    State.ki = State.ki - amount
    return true
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function damageScale()
    if State.superSaiyan then
        return Config.superSaiyan.damageScale
    end
    return 1.0
end

local function vecLength(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function vecNorm(v)
    local len = vecLength(v)
    if len < 0.001 then
        return vector3(0.0, 0.0, 0.0)
    end
    return vector3(v.x / len, v.y / len, v.z / len)
end

local function camForward()
    local rot = GetGameplayCamRot(2)
    local pitch = math.rad(rot.x)
    local yaw = math.rad(rot.z)
    return vector3(
        -math.sin(yaw) * math.abs(math.cos(pitch)),
        math.cos(yaw) * math.abs(math.cos(pitch)),
        math.sin(pitch)
    )
end

local function camRight()
    local fwd = camForward()
    return vecNorm(vector3(fwd.y, -fwd.x, 0.0))
end

local function loadPtfx(asset)
    if not HasNamedPtfxAssetLoaded(asset) then
        RequestNamedPtfxAsset(asset)
        local timeout = now() + 2000
        while not HasNamedPtfxAssetLoaded(asset) and now() < timeout do
            Wait(0)
        end
    end
    return HasNamedPtfxAssetLoaded(asset)
end

local function playPtfxAt(asset, effect, coords, scale)
    if loadPtfx(asset) then
        UseParticleFxAsset(asset)
        StartParticleFxNonLoopedAtCoord(
            effect,
            coords.x, coords.y, coords.z,
            0.0, 0.0, 0.0,
            scale or 1.0,
            false, false, false
        )
    end
end

local function drawKiBeam(fromCoords, toCoords, r, g, b, a)
    DrawLine(fromCoords.x, fromCoords.y, fromCoords.z, toCoords.x, toCoords.y, toCoords.z, r, g, b, a)
    DrawBox(
        toCoords.x - 0.12, toCoords.y - 0.12, toCoords.z - 0.12,
        toCoords.x + 0.12, toCoords.y + 0.12, toCoords.z + 0.12,
        r, g, b, a
    )
end

local function damagePedsInSphere(center, radius, damage, attacker)
    local handle, ped = FindFirstPed()
    local ok = true
    while ok do
        if ped ~= attacker and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pedCoords = GetEntityCoords(ped)
            local dist = #(pedCoords - center)
            if dist <= radius then
                ApplyDamageToPed(ped, math.floor(damage), false)
                AddExplosion(pedCoords.x, pedCoords.y, pedCoords.z, 0, 0.0, false, true, 0.0)
            end
        end
        ok, ped = FindNextPed(handle)
    end
    EndFindPed(handle)
end

local function getClosestHostile(origin, maxRange)
    local playerPed = PlayerPedId()
    local closest, closestDist = nil, maxRange
    local handle, ped = FindFirstPed()
    local ok = true

    while ok do
        if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, true) then
            local hostile = IsPedInCombat(ped, playerPed)
                or (GetRelationshipBetweenPeds(ped, playerPed) >= 4)
            if hostile then
                local dist = #(GetEntityCoords(ped) - origin)
                if dist < closestDist then
                    closest = ped
                    closestDist = dist
                end
            end
        end
        ok, ped = FindNextPed(handle)
    end
    EndFindPed(handle)
    return closest, closestDist
end

-- =============================================================================
-- HUD
-- =============================================================================

local function drawHud()
    local kiRatio = clamp(State.ki / Config.ki.max, 0.0, 1.0)
    local barW, barH = 0.18, 0.018
    local x, y = 0.86, 0.88

    DrawRect(x, y, barW + 0.006, barH + 0.01, 0, 0, 0, 160)
    DrawRect(x - (barW * (1.0 - kiRatio) * 0.5), y, barW * kiRatio, barH, 80, 180, 255, 220)

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextEntry("STRING")
    local mode = "Ki"
    if State.superSaiyan then
        mode = "SSJ"
    end
    if State.flying then
        mode = mode .. " | VUELO"
    end
    AddTextComponentString(string.format("%s  %.0f / %.0f", mode, State.ki, Config.ki.max))
    DrawText(x - barW * 0.5, y - 0.028)
end

-- =============================================================================
-- Super Saiyan / aura
-- =============================================================================

local function stopAura()
    if State.auraFx then
        StopParticleFxLooped(State.auraFx, false)
        State.auraFx = nil
    end
end

local function startAura(ped)
    stopAura()
    local asset = "core"
    if loadPtfx(asset) then
        UseParticleFxAsset(asset)
        State.auraFx = StartParticleFxLoopedOnEntity(
            "ent_amb_fbi_fire_drip",
            ped,
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            1.4,
            false, false, false
        )
    end
end

local function applySuperSaiyanStats(enabled)
    local player = PlayerId()
    local ped = PlayerPedId()

    if enabled then
        SetRunSprintMultiplierForPlayer(player, Config.superSaiyan.speedMultiplier)
        SetPedMoveRateOverride(ped, Config.superSaiyan.speedMultiplier)
        SetPlayerMeleeWeaponDamageModifier(player, Config.superSaiyan.meleeMultiplier)
        SetPedCanRagdoll(ped, false)
        SetEntityMaxHealth(ped, 250)
        if GetEntityHealth(ped) < 250 then
            SetEntityHealth(ped, 250)
        end
        SetPedArmour(ped, 100)
        startAura(ped)
    else
        SetRunSprintMultiplierForPlayer(player, 1.0)
        SetPedMoveRateOverride(ped, 1.0)
        SetPlayerMeleeWeaponDamageModifier(player, 1.0)
        SetPedCanRagdoll(ped, true)
        stopAura()
    end
end

local function toggleSuperSaiyan()
    if onCooldown("transform") or State.casting then
        return
    end

    if State.superSaiyan then
        State.superSaiyan = false
        applySuperSaiyanStats(false)
        notify("~y~Super Saiyan~s~ desactivado")
        markUsed("transform")
        return
    end

    if State.ki < Config.ki.transformCost then
        notify("~r~Ki insuficiente para transformarte")
        return
    end

    spendKi(Config.ki.transformCost)
    State.superSaiyan = true
    applySuperSaiyanStats(true)
    notify("~y~¡Super Saiyan!")
    markUsed("transform")
end

local function updateAuraLight(ped)
    if not State.superSaiyan then
        return
    end
    local c = GetEntityCoords(ped)
    local col = Config.superSaiyan.auraColor
    DrawLightWithRange(c.x, c.y, c.z + 0.6, col.r, col.g, col.b, 8.0, 4.0)
end

-- =============================================================================
-- Flight
-- =============================================================================

local function setFlight(enabled)
    local ped = PlayerPedId()
    State.flying = enabled
    SetEntityHasGravity(ped, not enabled)
    SetPedCanRagdoll(ped, not enabled)

    if enabled then
        ClearPedTasksImmediately(ped)
        notify("~b~Vuelo libre")
    else
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        notify("~b~Vuelo desactivado")
    end
end

local function updateFlight(dt)
    if not State.flying then
        return
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        setFlight(false)
        return
    end

    local boosting = IsControlPressed(0, Config.keys.boost)
    local hSpeed = boosting and Config.flight.boostSpeed or Config.flight.cruiseSpeed
    local vSpeed = boosting and Config.flight.boostVertical or Config.flight.verticalSpeed

    local move = vector3(0.0, 0.0, 0.0)
    local fwd = camForward()
    local right = camRight()

    if IsControlPressed(0, Config.keys.moveFwd) then
        move = move + fwd
    end
    if IsControlPressed(0, Config.keys.moveBack) then
        move = move - fwd
    end
    if IsControlPressed(0, Config.keys.moveRight) then
        move = move + right
    end
    if IsControlPressed(0, Config.keys.moveLeft) then
        move = move - right
    end

    local horizontal = vecNorm(vector3(move.x, move.y, 0.0))
    local vz = 0.0
    if IsControlPressed(0, Config.keys.ascend) then
        vz = vSpeed
    elseif IsControlPressed(0, Config.keys.descend) then
        vz = -vSpeed
    end

    local vx = horizontal.x * hSpeed
    local vy = horizontal.y * hSpeed

    if State.superSaiyan then
        vx = vx * Config.superSaiyan.speedMultiplier
        vy = vy * Config.superSaiyan.speedMultiplier
        vz = vz * Config.superSaiyan.speedMultiplier
    end

    SetEntityVelocity(ped, vx, vy, vz)
    SetEntityCollision(ped, true, true)

    if boosting then
        local c = GetEntityCoords(ped)
        playPtfxAt("core", "ent_sht_steam", c, 0.6)
    end
end

-- =============================================================================
-- Ki
-- =============================================================================

local function updateKi(dt)
    local ped = PlayerPedId()
    State.charging = IsControlPressed(0, Config.keys.chargeKi) and not State.casting

    if State.charging then
        State.ki = clamp(State.ki + Config.ki.chargePerSecond * dt, 0.0, Config.ki.max)
        local c = GetEntityCoords(ped)
        DrawLightWithRange(c.x, c.y, c.z + 0.4, 120, 200, 255, 6.0, 2.5)
        if loadPtfx("core") then
            UseParticleFxAsset("core")
            StartParticleFxNonLoopedOnEntity(
                "ent_amb_sparking_wires",
                ped,
                0.0, 0.0, 0.8,
                0.0, 0.0, 0.0,
                0.8,
                false, false, false
            )
        end
    elseif State.superSaiyan then
        State.ki = clamp(State.ki - Config.ki.superSaiyanDrainPerSecond * dt, 0.0, Config.ki.max)
        if State.ki <= 0.0 then
            State.superSaiyan = false
            applySuperSaiyanStats(false)
            notify("~r~Ki agotado. Transformación rota")
        end
    else
        State.ki = clamp(State.ki + Config.ki.idleRegenPerSecond * dt, 0.0, Config.ki.max)
    end
end

-- =============================================================================
-- Attacks
-- =============================================================================

local function executeKamehameha()
    if State.casting or onCooldown("kamehameha") then
        if onCooldown("kamehameha") then
            notify("~r~Kamehameha cooldown: " .. remainingCooldown("kamehameha") .. "s")
        end
        return
    end
    if not spendKi(Config.ki.kamehamehaCost) then
        notify("~r~Ki insuficiente para Kamehameha")
        return
    end

    State.casting = true
    markUsed("kamehameha")

    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        TaskStandStill(ped, 1600)
        notify("~b~Kamehameha...")
        Wait(700)

        local origin = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.55)
        local dir = vecNorm(camForward())
        local range = Config.combat.kamehamehaRange
        local steps = 28
        local dmg = Config.combat.kamehamehaDamage * damageScale()

        for i = 1, steps do
            local t = i / steps
            local point = origin + dir * (range * t)
            drawKiBeam(origin, point, 80, 160, 255, 220)
            playPtfxAt("core", "exp_grd_bzgas_smoke", point, 0.35)
            damagePedsInSphere(point, Config.combat.kamehamehaRadius, dmg / steps * 4.0, ped)
            Wait(20)
        end

        local impact = origin + dir * range
        AddExplosion(impact.x, impact.y, impact.z, 2, 0.8 * damageScale(), true, false, 0.45)
        damagePedsInSphere(impact, 6.0, dmg, ped)

        State.casting = false
    end)
end

local function executeKiBarrage()
    if State.casting or onCooldown("kiBlast") then
        return
    end
    if State.ki < Config.ki.kiBlastCost then
        notify("~r~Ki insuficiente")
        return
    end

    State.casting = true
    markUsed("kiBlast")

    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        local shots = Config.combat.kiBlastCount
        local dmg = Config.combat.kiBlastDamage * damageScale()

        for i = 1, shots do
            if not spendKi(Config.ki.kiBlastCost) then
                break
            end

            ped = PlayerPedId()
            local origin = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.5)
            local dir = vecNorm(camForward())
            local dest = origin + dir * Config.combat.kiBlastRange

            drawKiBeam(origin, dest, 180, 220, 255, 200)
            playPtfxAt("core", "muz_railgun", origin + dir * 1.2, 0.8)

            ShootSingleBulletBetweenCoords(
                origin.x, origin.y, origin.z,
                dest.x, dest.y, dest.z,
                math.floor(dmg),
                true,
                GetHashKey("WEAPON_COMBATPISTOL"),
                ped,
                true,
                true,
                800.0
            )
            damagePedsInSphere(origin + dir * 8.0, 2.2, dmg * 0.35, ped)
            Wait(Config.combat.kiBlastIntervalMs)
        end

        State.casting = false
    end)
end

local function executeInstantTransmission()
    if State.casting or onCooldown("instantTransmission") then
        if onCooldown("instantTransmission") then
            notify("~r~Instant Transmission cooldown: " .. remainingCooldown("instantTransmission") .. "s")
        end
        return
    end
    if not spendKi(Config.ki.instantTransmissionCost) then
        notify("~r~Ki insuficiente para Instant Transmission")
        return
    end

    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local target = select(1, getClosestHostile(origin, Config.combat.instantTransmissionRange))

    if not target then
        State.ki = clamp(State.ki + Config.ki.instantTransmissionCost, 0.0, Config.ki.max)
        notify("~r~No hay enemigos cerca")
        return
    end

    markUsed("instantTransmission")
    playPtfxAt("scr_rcbarry2", "scr_clown_appears", origin, 0.6)

    local tCoords = GetEntityCoords(target)
    local forward = GetEntityForwardVector(target)
    local behind = tCoords - (forward * 1.8)
    behind = vector3(behind.x, behind.y, tCoords.z)

    SetEntityCoords(ped, behind.x, behind.y, behind.z, false, false, false, false)
    SetEntityHeading(ped, GetEntityHeading(target))
    playPtfxAt("scr_rcbarry2", "scr_clown_appears", behind, 0.6)
    TaskCombatPed(target, ped, 0, 16)
    notify("~p~Instant Transmission")
end

-- =============================================================================
-- Enemy spawn / fight system
-- =============================================================================

local function ensureFighterGroup()
    if State.fighterGroup then
        return
    end
    local _, group = AddRelationshipGroup("DBZ_FIGHTERS")
    State.fighterGroup = group
    SetRelationshipBetweenGroups(5, group, GetHashKey("PLAYER"))
    SetRelationshipBetweenGroups(5, GetHashKey("PLAYER"), group)
end

local function cleanupDeadSpawns()
    local alive = {}
    for i = 1, #State.spawnedPeds do
        local ped = State.spawnedPeds[i]
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            alive[#alive + 1] = ped
        elseif DoesEntityExist(ped) then
            SetPedAsNoLongerNeeded(ped)
        end
    end
    State.spawnedPeds = alive
end

local function spawnHostileFighters()
    if onCooldown("spawnEnemies") then
        notify("~r~Spawn cooldown: " .. remainingCooldown("spawnEnemies") .. "s")
        return
    end

    ensureFighterGroup()
    cleanupDeadSpawns()

    local playerPed = PlayerPedId()
    local origin = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    local count = Config.combat.spawnCount

    for i = 1, count do
        local model = GetHashKey(Config.spawnModels[((i - 1) % #Config.spawnModels) + 1])
        RequestModel(model)
        local timeout = now() + 3000
        while not HasModelLoaded(model) and now() < timeout do
            Wait(0)
        end
        if HasModelLoaded(model) then
            local angle = heading + 40.0 * (i - 2)
            local rad = math.rad(angle)
            local pos = vector3(
                origin.x + math.cos(rad) * Config.combat.spawnDistance,
                origin.y + math.sin(rad) * Config.combat.spawnDistance,
                origin.z
            )
            local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 5.0, false)
            if found then
                pos = vector3(pos.x, pos.y, groundZ)
            end

            local enemy = CreatePed(4, model, pos.x, pos.y, pos.z, heading + 180.0, true, true)
            if DoesEntityExist(enemy) then
                SetPedRelationshipGroupHash(enemy, State.fighterGroup)
                SetPedArmour(enemy, 50)
                SetEntityMaxHealth(enemy, 200)
                SetEntityHealth(enemy, 200)
                SetPedCombatAbility(enemy, 2)
                SetPedCombatMovement(enemy, 2)
                SetPedCombatRange(enemy, 2)
                SetPedFleeAttributes(enemy, 0, false)
                SetPedCombatAttributes(enemy, 46, true)
                SetPedCombatAttributes(enemy, 5, true)
                GiveWeaponToPed(enemy, GetHashKey("WEAPON_UNARMED"), 0, false, true)
                SetPedAsEnemy(enemy, true)
                TaskCombatPed(enemy, playerPed, 0, 16)
                State.spawnedPeds[#State.spawnedPeds + 1] = enemy
            end
            SetModelAsNoLongerNeeded(model)
        end
    end

    markUsed("spawnEnemies")
    notify("~o~Enemigos invocados. ¡Pelea!")
end

-- =============================================================================
-- Input / main loop
-- =============================================================================

local function handleInput()
    if State.casting then
        return
    end

    if IsControlJustPressed(0, Config.keys.flightToggle) then
        setFlight(not State.flying)
    end
    if IsControlJustPressed(0, Config.keys.transform) then
        toggleSuperSaiyan()
    end
    if IsControlJustPressed(0, Config.keys.kamehameha) then
        executeKamehameha()
    end
    if IsDisabledControlJustPressed(0, Config.keys.kiBlast) or IsControlJustPressed(0, Config.keys.kiBlast) then
        executeKiBarrage()
    end
    if IsControlJustPressed(0, Config.keys.instantTransmission) then
        executeInstantTransmission()
    end
    if IsControlJustPressed(0, Config.keys.spawnEnemies) then
        spawnHostileFighters()
    end
end

Citizen.CreateThread(function()
    loadPtfx("core")
    loadPtfx("scr_rcbarry2")
    State.lastFrame = now()
    notify("~b~Dragon Ball combat listo. X vuelo | R Ki | F SSJ | E Kame | RMB ráfaga | Q IT | G spawn")

    while true do
        Wait(0)
        local t = now()
        local dt = clamp((t - State.lastFrame) / 1000.0, 0.0, 0.05)
        State.lastFrame = t

        handleInput()
        updateFlight(dt)
        updateKi(dt)
        updateAuraLight(PlayerPedId())
        drawHud()
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    stopAura()
    if State.flying then
        setFlight(false)
    end
    for i = 1, #State.spawnedPeds do
        if DoesEntityExist(State.spawnedPeds[i]) then
            DeletePed(State.spawnedPeds[i])
        end
    end
end)
