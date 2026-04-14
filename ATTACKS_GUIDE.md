# Guía de Atributos de Ataques — KoFLike

Referencia completa de todas las propiedades configurables para definir ataques en los archivos de personaje (e.g. `Ryu.luau`, `Ken.luau`).

---

## Índice

1. [Identificación y Timing](#1-identificación-y-timing)
2. [Animación y Sonido](#2-animación-y-sonido)
3. [Daño y Reacción al Golpe](#3-daño-y-reacción-al-golpe)
4. [Bloqueo](#4-bloqueo)
5. [Lanzamiento y Combos Aéreos](#5-lanzamiento-y-combos-aéreos)
6. [Hitbox](#6-hitbox)
7. [Dash durante Ataque](#7-dash-durante-ataque)
8. [Salto durante Ataque](#8-salto-durante-ataque)
9. [Proyectiles](#9-proyectiles)
10. [Efectos Visuales (VFX)](#10-efectos-visuales-vfx)
11. [Flash de Extremidad](#11-flash-de-extremidad)
12. [Restricciones de Ejecución](#12-restricciones-de-ejecución)
13. [Cancelación (Combo System)](#13-cancelación-combo-system)
14. [Ejemplo Completo](#14-ejemplo-completo)

---

## 1. Identificación y Timing

Estos definen la identidad del ataque y sus frames de ejecución. Los frames se calculan como `frames / 60` para obtener segundos.

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `Id` | `string` | ✅ | `"Punch"` | Identificador único del ataque. Se usa para replicar VFX, proyectiles y sincronización. |
| `Startup` | `number` | ✅ | `4 / 60` | Tiempo (segundos) antes de que la hitbox se active. El personaje está en animación pero no puede golpear. |
| `Active` | `number` | ✅ | `4 / 60` | Tiempo (segundos) que la hitbox permanece activa y puede conectar. |
| `Recovery` | `number` | ✅ | `12 / 60` | Tiempo (segundos) después de active donde el personaje no puede actuar. |

**Duración total del ataque** = `Startup + Active + Recovery`

### Funciones que los usan

- **`CombatController:RegisterStates()` → estado `Attack.Enter`**: Usa `Startup` para hacer `task.delay` antes de crear la hitbox. Usa `Active` para destruir la hitbox. Usa `Startup + Active + Recovery` para liberar el `attackLocked`.
- **`ProjectileService.Spawn()`**: Usa `Startup` para retrasar el spawn del proyectil.

---

## 2. Animación y Sonido

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `Animation` | `string` | ⚠️ | `"HeavyPunch"` | Nombre base de la animación a reproducir (se le agrega `_R` o `_L`). |
| `AnimationBase` | `string` | ⚠️ | `"Punch"` | Alternativa a `Animation`. Se usa para ataques con combo (Punch → Punch2 → Punch3). El sistema agrega el número del combo automáticamente. |
| `SoundEffect` | `string` | ❌ | `"Punch"` | Nombre del sonido a reproducir al iniciar el ataque. |
| `SoundVolume` | `number` | ❌ | `0.7` | Volumen del sonido (0.0 a 1.0). Default: `0.5`. |

> ⚠️ Se requiere al menos `Animation` o `AnimationBase`. Si ambos existen, se prefiere `Animation`.

### Funciones que los usan

- **`CombatController:RegisterStates()` → `Attack.Enter`**: Lee `self.context.currentAnimationName or attack.Animation or attack.AnimationBase` y llama a `AnimationController:PlayAnimation()`.
- **`CombatController:RequestAttack()`**: Para ataques tipo `Punch` con combo, lee `AnimationBase` y le concatena el número de combo (`"Punch" + 2 = "Punch2"`).
- **`SoundManager.PlaySound()`**: Recibe `SoundEffect` y `SoundVolume`.

---

## 3. Daño y Reacción al Golpe

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `Damage` | `number` | ✅ | `10` | Daño base infligido al conectar. |
| `HitType` | `string` | ✅ | `"Light"` | Tipo de golpe. Valores: `"Light"`, `"Heavy"`, `"Special"`. Afecta la reacción visual. |
| `HitAnimation` | `string` | ✅ | `"HurtLight"` | Animación que reproduce la víctima al ser golpeada. Se sobrescribe a `"AirHurt"` si la víctima está en el aire, o `"Launch"` si tiene `LaunchForce`. |
| `HitstunDuration` | `number` | ✅ | `0.22` | Duración (segundos) que la víctima permanece en hitstun sin poder actuar. Se reduce por juggle decay en combos aéreos. |
| `Pushback` | `number` | ✅ | `5` | Distancia (studs) que la víctima retrocede al ser golpeada. Se aplica como velocidad horizontal tras el hitstop. |
| `HitstopFrames` | `number` | ✅ | `5` | Frames de congelamiento (hitfreeze) al conectar. Ambos personajes se pausan. 0 = sin hitstop. |
| `Knockdown` | `boolean` | ✅ | `false` | Si `true`, la víctima entra en estado `Knockdown` tras el hitstun (caída al suelo con wakeup). |

### Funciones que los usan

- **`CombatController:ApplyHitReaction()`**: Lee `HitAnimation`, `HitstunDuration`, `HitstopFrames`, `Knockdown`, `Pushback`. Aplica juggle decay si la víctima está en el aire.
- **`CombatController:ApplyLocalHitPrediction()`**: Lee `Pushback`, `HitstunDuration`, `HitAnimation`, `HitstopFrames`, `Knockdown` para predicción visual del oponente.
- **`CombatController:_applyPostHitstopPushback()`**: Usa `Pushback` para mover a la víctima después del hitstop.
- **`CombatController:_bindHitListener()`**: Lee todos estos valores desde los Attributes del Character replicados por el servidor.
- **`HitstopService:Apply()`**: Recibe `HitstopFrames` para congelar animaciones y personajes.
- **`DamageService`**: Recibe `Damage` desde el servidor (vía `attackData`).
- **`VFXService.HurtFlash()`**: Recibe `HitstopFrames` para determinar duración del flash de daño.

---

## 4. Bloqueo

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `AttackHeight` | `string` | ✅ | `"Mid"` | Determina qué tipo de guardia lo bloquea. |
| `BlockPushback` | `number` | ✅ | `6` | Distancia que retrocede el defensor al bloquear. |
| `BlockstunDuration` | `number` | ✅ | `0.15` | Duración del blockstun (el defensor no puede actuar). |
| `ChipDamage` | `number` | ✅ | `0` | Daño que se inflige incluso al bloquear (chip damage). Los ataques light normalmente tienen 0. |

### Valores de `AttackHeight`

| Valor | Se bloquea con | Descripción |
|-------|----------------|-------------|
| `"Mid"` | Guardia parada o agachada | Golpe medio, se bloquea siempre. |
| `"High"` | Solo guardia parada | Golpe alto, no se bloquea agachado. |
| `"Low"` | Solo guardia agachada | Golpe bajo (barrida), no se bloquea parado. |
| `"Unblockable"` | No se puede bloquear | Ignora cualquier guardia. |

### Funciones que los usan

- **`CombatController:_checkBlock()`**: Compara `AttackHeight` con el tipo de guardia actual (`"High"` o `"Low"`) para determinar si el golpe es bloqueado.
- **`CombatController:ApplyBlockReaction()`**: Usa `BlockPushback`, `BlockstunDuration`, `ChipDamage`.

---

## 5. Lanzamiento y Combos Aéreos

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `LaunchForce` | `number?` | ❌ | `45` | Fuerza vertical para lanzar a la víctima al aire. `nil` o `0` = no lanza. Afectado por el Weight de la víctima y juggle decay. |
| `HorizontalLaunch` | `number?` | ❌ | `10` | Componente horizontal del lanzamiento. Empuja a la víctima en la dirección opuesta al atacante. |

### Sistema de Juggle Decay

Cada golpe aéreo sucesivo reduce la efectividad:

```
decayMultiplier = max(0.2, 1 - (juggleCount × juggleDecay))
```

Donde `juggleDecay` default = `0.15` (15% menos por golpe).

### Sistema de Peso (Weight)

```
weightMultiplier = 1 / max(0.3, victimWeight)
```

- Personajes ligeros (`Weight < 1.0`) → vuelan más lejos
- Personajes pesados (`Weight > 1.0`) → vuelan menos

### Funciones que los usan

- **`CombatController:ApplyHitReaction()`**: Lee `LaunchForce` y `HorizontalLaunch`. Si `LaunchForce > 0` y la víctima está en el suelo, la lanza al aire con `HitAnimation = "Launch"`. Si ya está en el aire, aplica re-launch con decay.

---

## 6. Hitbox

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `Hitbox` | `table` | ✅ | `{ Size = ..., Offset = ... }` | Tabla que define la zona de colisión del ataque. |
| `Hitbox.Size` | `Vector3` | ✅ | `Vector3.new(4, 5, 4)` | Dimensiones de la hitbox (ancho, alto, profundidad). |
| `Hitbox.Offset` | `Vector3` | ✅ | `Vector3.new(0, 0, -2)` | Posición relativa al `HumanoidRootPart`. Negativo en Z = hacia adelante del personaje. Negativo en Y = abajo. |

### Funciones que los usan

- **`Hitbox.new(root, hitboxData)`**: En `Hitbox.luau`, crea un Part invisible posicionado en `root.CFrame * CFrame.new(Offset)` con tamaño `Size`. Detecta colisión con `HurtboxBody` usando `GetPartBoundsInBox`.
- **`ProjectileService.Spawn()`**: Usa `Hitbox.Size` como tamaño del proyectil y `Hitbox.Offset` como posición inicial.

---

## 7. Dash durante Ataque (AttackDash)

Permite que el personaje se desplace horizontalmente durante la animación del ataque. Útil para ataques que avanzan (lunge punch) o retroceden (heavy con retreating).

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `AttackDash` | `boolean` | ❌ | `true` | Activa el sistema de dash. **Sin esto, las demás propiedades de dash se ignoran.** |
| `DashDistance` | `number` | ❌ | `4` | Distancia total en studs. **Positivo** = avanza en la dirección que mira. **Negativo** = retrocede. |
| `DashFrameStart` | `number` | ❌ | `3` | Frame del ataque en que comienza el dash. Default: `1`. |
| `DashDuration` | `number` | ❌ | `5` | Duración del dash en frames. Default: `4`. |
| `DashLiftY` | `number` | ❌ | `8` | Impulso vertical al iniciar el dash. Útil para ataques aéreos que suben ligeramente (como un air dash en juegos de pelea). Solo se aplica una vez al inicio. |

### Velocidad del dash

```
distPerFrame = abs(DashDistance) / DashDuration
```

Cada frame dentro del rango `[DashFrameStart, DashFrameStart + DashDuration]` mueve al personaje `distPerFrame` studs.

### Dirección

- Si `DashDistance > 0`: se mueve **hacia donde mira** el personaje
- Si `DashDistance < 0`: se mueve **en dirección opuesta** (retrocede)

### Funciones que los usan

- **`CombatController:RegisterStates()` → `Attack.Enter`**: Verifica `attack.AttackDash and attack.DashDistance and attack.DashDistance ~= 0`. Crea una conexión a `RenderStepped` que mueve al personaje usando `CharacterMotor:MoveCurrentX()`.
- **`CharacterMotor:MoveCurrentX()`**: Ejecuta el movimiento respetando colisiones con otros personajes.
- Al iniciar el dash, si `DashLiftY > 0`, aplica `root.AssemblyLinearVelocity.Y = DashLiftY`.

### Ejemplo: Retroceso al golpear

```lua
AttackDash = true,
DashDistance = -5,     -- negativo = retrocede
DashFrameStart = 2,
DashDuration = 6,
```

### Ejemplo: Dash aéreo con subida

```lua
AttackDash = true,
DashDistance = 4,
DashFrameStart = 3,
DashDuration = 5,
DashLiftY = 8,        -- impulso vertical al iniciar
```

---

## 8. Salto durante Ataque (AttackJump)

Permite que el personaje salte durante la ejecución del ataque. Usado para ataques tipo Shoryuken/Dragon Punch.

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `AttackJump` | `boolean` | ❌ | `true` | Activa el sistema de salto durante ataque. |
| `JumpHeight` | `number` | ❌ | `40` | Velocidad vertical (studs/s) aplicada al `AssemblyLinearVelocity.Y`. |
| `JumpFrameStart` | `number` | ❌ | `3` | Frame del ataque en que se aplica el salto. Default: `1`. |

### Funciones que los usan

- **`CombatController:RegisterStates()` → `Attack.Enter`**: Verifica `attack.AttackJump and attack.JumpHeight and attack.JumpHeight > 0`. Crea conexión a `RenderStepped` que espera al frame correcto y aplica la velocidad vertical. Solo se aplica una vez. Marca `isAirborne = true`.

### Ejemplo: Shoryuken

```lua
AttackJump = true,
JumpHeight = 40,
JumpFrameStart = 3,
-- Combinado con AttackDash para avance horizontal
AttackDash = true,
DashDistance = 3,
DashFrameStart = 1,
DashDuration = 4,
```

---

## 9. Proyectiles

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `IsProjectile` | `boolean` | ❌ | `true` | El ataque genera un proyectil en vez de hitbox local. |
| `ProjectileSpeed` | `number` | ❌ | `40` | Velocidad del proyectil en studs/s. Default: `40`. |
| `ProjectileLifetime` | `number` | ❌ | `1.5` | Tiempo de vida en segundos antes de destruirse. Default: `1.5`. |

### Funciones que los usan

- **`CombatController:RegisterStates()` → `Attack.Enter`**: Si `attack.IsProjectile`, en lugar de crear hitbox local, llama a `ProjectileService.Spawn()` tras el delay de `Startup`.
- **`ProjectileService.Spawn()`**: Crea un Part Neon que se mueve en el eje X a `ProjectileSpeed` studs/s. Detecta colisión con `HurtboxBody` cada frame. Se destruye al colisionar o al superar `ProjectileLifetime`. Usa `Hitbox.Size` para el tamaño del proyectil y `Hitbox.Offset` para posición inicial.

---

## 10. Efectos Visuales (VFX)

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `VFX` | `table?` | ❌ | `{ Startup = "Startup", Active = "Active" }` | Tabla con nombres de efectos visuales por fase. |
| `VFX.Startup` | `string?` | ❌ | `"Startup"` | Efecto que se reproduce al **iniciar** el ataque (inmediato). Duración = `Startup`. |
| `VFX.Active` | `string?` | ❌ | `"Active"` | Efecto que se reproduce durante los frames **activos**. Se retrasa `Startup` segundos. |
| `VFX.ActiveTrail` | `string?` | ❌ | `"ActiveTrail"` | Trail (estela) que se activa durante activo. Se enciende al inicio y se apaga tras `Startup + Active`. |
| `VFX.OnHit` | `string?` | ❌ | `"OnHit"` | Efecto en el punto de impacto al **conectar** el golpe. |
| `VFX_Limb` | `string?` | ❌ | `"RightHand"` | Extremidad donde se posicionan los VFX. |
| `VFX_Limbs` | `{string}?` | ❌ | `{"RightHand", "LeftHand", "RightFoot"}` | Lista de extremidades para combos. Se rota según `punchComboCount`. |

### Extremidades válidas

`"RightHand"`, `"LeftHand"`, `"RightFoot"`, `"LeftFoot"`, `"Head"`, `"Torso"`, `"Root"`

### Prioridad de VFX_Limb

1. Si `VFX_Limbs` existe y tiene elementos → usa el que corresponda al hit del combo: `VFX_Limbs[((comboIndex - 1) % #VFX_Limbs) + 1]`
2. Si no, usa `VFX_Limb`
3. Default: `"RightHand"`

### Funciones que los usan

- **`CombatController:RegisterStates()` → `Attack.Enter`**:
  - `VFX.Startup` → `VFXService.Play()` inmediato con `forceBurst = true`
  - `VFX.Active` → `VFXService.Play()` retrasado por `Startup`
  - `VFX.ActiveTrail` → `VFXService.EnableTrail()` on/off
  - `VFX_Limb`/`VFX_Limbs` → determina en qué Part del personaje se reproduce el efecto
- **Hitbox `onHit` callback**: `VFX.OnHit` → `VFXService.PlayAtPosition()` en el punto de colisión.
- **ReplicateVFXEvent**: Replica todos los VFX al oponente para que los vea en su cliente.
- **`ProjectileService.Spawn()`**: Usa `VFX.OnHit` para efecto visual al impactar.

### Estructura de carpetas VFX

Los VFX se buscan en: `Characters/<PersonajeName>/VFX/<AttackId>/<VFXName>`

Ejemplo: `Characters/Ryu/VFX/Punch/Startup`

---

## 11. Flash de Extremidad (HitLimbFlash)

Efecto visual de "brillo" en la extremidad que ataca. Se reproduce al **iniciar** el ataque (no al conectar).

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `HitLimbFlash` | `table?` | ❌ | `{ Enabled = true, ... }` | Configuración del flash. |
| `HitLimbFlash.Enabled` | `boolean` | ✅* | `true` | Activa/desactiva el flash. |
| `HitLimbFlash.Color` | `string` | ❌ | `"Red"` | Color del flash. |
| `HitLimbFlash.FillTransparency` | `number` | ❌ | `0.8` | Transparencia del relleno (0–1). |
| `HitLimbFlash.OutlineTransparency` | `number` | ❌ | `0.2` | Transparencia del borde (0–1). |

> \* Solo se procesa si `HitLimbFlash.Enabled == true`.

### Duración automática

```
Duration = Startup + Active
```

### Funciones que los usan

- **`CombatController:RegisterStates()` → `Attack.Enter`**: Si `Enabled`, clona la config, le agrega `Duration`, llama a `VFXService.AttackLimbFlash()`.
- **ReplicateVFXEvent**: Replica la config al oponente.

---

## 12. Restricciones de Ejecución

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `GroundOnly` | `boolean` | ❌ | `true` | Si `true`, solo se puede ejecutar en el suelo. |
| `AirOk` | `boolean` | ❌ | `true` | Si `true`, solo se puede ejecutar **en el aire**. Si `true` y el personaje está en suelo, se bloquea. |
| `IsSpecial` | `boolean` | ❌ | `true` | Marca como movimiento especial. Los especiales **no** se remapean a versión crouch. Un `Fireball` se ejecuta igual estando agachado o parado. |

### Mapeo automático de ataques

Cuando el personaje está en estados específicos, el sistema remapea automáticamente:

**En el aire** (`isAirborne = true`):
```
Punch     → AirPunch
HeavyPunch → AirHeavy
```

**Agachado** (`isCrouching = true`, excepto si `IsSpecial`):
```
Punch      → CrouchPunch
HeavyPunch → CrouchHeavy
```

### Funciones que los usan

- **`CombatController:RequestAttack()`**:
  - Verifica `GroundOnly` implícitamente vía el mapeo (solo ataques con `AirOk` se ejecutan en el aire).
  - Si `AirOk and not isAirborne` → bloquea el ataque.
  - Si `IsSpecial` → omite el remapeo a crouch.
  - Aplica mapeo aéreo o crouch según estado.

---

## 13. Cancelación (Combo System)

| Propiedad | Tipo | Requerido | Ejemplo | Descripción |
|-----------|------|-----------|---------|-------------|
| `CancelWindow` | `table?` | ❌ | `{ Start = 8, End = 14 }` | Rango de frames donde se puede cancelar en otro ataque (combo link). |
| `CancelWindow.Start` | `number` | ✅* | `8` | Frame inicial de la ventana de cancelación. |
| `CancelWindow.End` | `number` | ✅* | `14` | Frame final de la ventana de cancelación. |

> \* Requeridos si `CancelWindow` existe.

Si `CancelWindow = nil`, el ataque **no** se puede cancelar en ningún momento.

### Funciones que los usan

- **`CombatController:RegisterStates()` → `Attack.Update`**: Cada frame revisa si `attackFrame` está dentro de `[CancelWindow.Start, CancelWindow.End]` y setea `context.canCancel = true/false`.
- **`CombatController:RequestAttack()`**: Si el estado actual es `"Attack"` y `canCancel == false`, bloquea el nuevo ataque.

---

## 14. Ejemplo Completo

```lua
-- Ataque completo con todas las propiedades posibles
Character.Attacks.ExampleAttack = {
    -- Identificación y Timing
    Id = "ExampleAttack",
    Startup = 6 / 60,          -- 6 frames de startup
    Active = 4 / 60,           -- 4 frames activos
    Recovery = 14 / 60,        -- 14 frames de recovery

    -- Animación y Sonido
    Animation = "ExampleAttack",   -- o AnimationBase para combos
    SoundEffect = "Punch",
    SoundVolume = 0.8,

    -- Daño y Reacción
    Damage = 15,
    HitType = "Heavy",
    HitAnimation = "HurtLight",
    AttackHeight = "Mid",
    HitstunDuration = 0.35,
    Pushback = 6,
    HitstopFrames = 7,
    Knockdown = false,

    -- Lanzamiento (opcional)
    LaunchForce = 45,           -- lanza al aire
    HorizontalLaunch = 10,     -- empuja horizontalmente al lanzar

    -- Bloqueo
    BlockPushback = 8,
    BlockstunDuration = 0.2,
    ChipDamage = 2,

    -- Restricciones
    GroundOnly = false,
    AirOk = false,              -- true = solo aéreo
    IsSpecial = false,          -- true = no se remapea a crouch

    -- Hitbox
    Hitbox = {
        Size = Vector3.new(4, 5, 4),
        Offset = Vector3.new(0, 0, -3),
    },

    -- Dash durante ataque
    AttackDash = true,
    DashDistance = 5,           -- negativo = retrocede
    DashFrameStart = 2,
    DashDuration = 4,
    DashLiftY = 0,             -- > 0 = impulso vertical al iniciar

    -- Salto durante ataque (tipo Shoryuken)
    AttackJump = true,
    JumpHeight = 40,
    JumpFrameStart = 3,

    -- Proyectil (tipo Hadouken, excluye hitbox local)
    IsProjectile = true,
    ProjectileSpeed = 40,
    ProjectileLifetime = 1.5,

    -- VFX
    VFX = {
        Startup = "Startup",
        Active = "Active",
        ActiveTrail = "ActiveTrail",
        OnHit = "OnHit",
    },
    VFX_Limb = "RightHand",
    -- o VFX_Limbs para combos:
    -- VFX_Limbs = { "RightHand", "LeftHand", "RightFoot" },

    -- Flash de extremidad
    HitLimbFlash = {
        Enabled = true,
        Color = "Red",
        FillTransparency = 0.8,
        OutlineTransparency = 0.2,
    },

    -- Cancel Window
    CancelWindow = { Start = 8, End = 14 },
}
```

> **Nota:** No todos los atributos deben estar presentes. Solo `Id`, `Startup`, `Active`, `Recovery`, `Animation`/`AnimationBase`, `Damage`, `HitType`, `HitAnimation`, `AttackHeight`, `HitstunDuration`, `Pushback`, `HitstopFrames`, `BlockPushback`, `BlockstunDuration`, `ChipDamage`, y `Hitbox` son necesarios para un ataque funcional. Los demás son opcionales y activan funcionalidades adicionales.

---

## Resumen de Archivos Relevantes

| Archivo | Rol |
|---------|-----|
| `CombatController.luau` | Lee y ejecuta todas las propiedades de ataque. Estados Attack, Hitstun, block logic, RequestAttack, hit reactions. |
| `AnimationController.luau` | Reproduce las animaciones según `Animation`/`AnimationBase`. |
| `CharacterMotor.luau` | Ejecuta `MoveCurrentX()` para el dash. Maneja estado aéreo. |
| `Hitbox.luau` | Crea Part de colisión con `Hitbox.Size` y `Hitbox.Offset`. |
| `ProjectileService.luau` | Spawn y movimiento de proyectiles. |
| `VFXService.luau` | Reproduce efectos visuales, trails, flashes. |
| `SoundManager.luau` | Reproduce efectos de sonido. |
| `HitstopService.luau` | Congela personajes y animaciones durante hitstop. |
| `DamageService.luau` | Aplica daño desde el servidor. |
