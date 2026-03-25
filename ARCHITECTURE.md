# KoFLike — Arquitectura del Proyecto

Juego de peleas 2.5D estilo KOF/DBFZ/Brawlhalla en Roblox (Luau).  
Movimiento en eje X, Z bloqueado, cámara lateral dinámica.

---

## Estructura de Carpetas

```
src/
├── Client/                          # Scripts que corren en el cliente
│   ├── CharacterScripts/
│   │   └── InputClient              # Captura teclado/mouse → traduce a comandos
│   └── PlayerScripts/
│       ├── DebugInputTest            # Debug de inputs (deshabilitado)
│       ├── InitializeDummy           # Inicializa el dummy de entrenamiento en el cliente
│       └── UIManager                 # Crea menú principal y HUD, maneja modos de juego
│
├── Server/                          # Scripts que corren en el servidor
│   ├── script                        # Placeholder (sin lógica)
│   ├── GameServer                    # Crea RemoteEvents, rutea modos de juego, replica animaciones
│   ├── DamageHandler                 # Valida hits, aplica daño, transfiere NetworkOwnership
│   ├── HurtboxServer                 # Crea hurtbox para cada jugador al spawnear
│   └── TrainingDummyServer           # Crea hurtbox para dummies de entrenamiento
│
└── Shared/Modules/                  # Módulos compartidos (ReplicatedStorage)
    ├── CharacterControllers/        # Sistema de control principal del jugador
    │   ├── CharacterController       # Orquestador: crea Motor, Combat, Animation; loop principal
    │   ├── CharacterMotor            # Movimiento: walk, push, jump, dodge, plane lock, colisión
    │   ├── CombatController          # Combate: hit reactions, hitstun, knockdown, predicción
    │   └── AnimationController       # Carga y reproduce animaciones per-character con dirección (_R/_L)
    │
    ├── Characters/                  # Sistema de personajes
    │   ├── BaseCharacter             # Clase padre: Info, Attacks, Commands, Skins, GetAnimationsFolder()
    │   ├── CharacterRegistry         # Registro central de personajes disponibles
    │   ├── Ryu/                      # Template #1: equilibrado, fireball + uppercut
    │   │   ├── Ryu                   # Datos del personaje (Info, Attacks, Commands, Skins)
    │   │   └── Animations/Test/      # Animaciones propias de Ryu (_R/_L)
    │   └── Ken/                      # Template #2: rushdown agresivo, más rápido
    │       ├── Ken                   # Datos del personaje
    │       └── Animations/Test/      # Animaciones propias de Ken (_R/_L)
    │
    ├── Combat/                      # Sistemas de combate individuales
    │   ├── Attacks                   # Tabla GLOBAL de ataques (fallback si no hay personaje)
    │   ├── Hitbox                    # Crea hitbox temporal, detecta colisión con hurtboxes
    │   ├── Hurtbox                   # Crea hurtbox weldeada al HumanoidRootPart
    │   ├── DamageService             # Cliente: envía FireServer con datos del ataque
    │   ├── HitstopService            # Congela animaciones y movimiento por N frames
    │   ├── DummyController           # IA del dummy: recibe hits, pushback, regen (per-character anims)
    │   ├── CameraHandler             # Cámara lateral 2.5D con zoom dinámico
    │   ├── SoundManager              # Reproduce efectos de sonido posicionales
    │   ├── InputBuffer               # Buffer temporal de inputs con match de secuencias
    │   ├── CommandParser             # Parsea buffer (soporta comandos por personaje o globales)
    │   ├── CommandList               # Define secuencias de input GLOBALES → nombre de comando
    │   ├── StateMachine              # FSM genérica: AddState, SetState, Update
    │   └── CharacterController_Legacy # Versión anterior (no se usa, referencia)
    │
    ├── UI/                          # Sistema de UI basado en componentes
    │   ├── Component                 # Clase base con setState/destroy (estilo React)
    │   ├── UIBuilder                 # Factory de elementos de UI con helpers
    │   └── Components/
    │       ├── MainMenuComponent     # Menú principal: Training / Versus
    │       ├── GameHUDComponent      # HUD de pelea: barras de vida, timer
    │       ├── PlayMenuComponent     # Selección de modo de juego
    │       ├── CharacterSelectComponent # Selección de personaje (simple o dual para Training)
    │       └── PlaceholderScreen     # Pantallas "Coming soon"
    │
    └── Utilities/
        └── GameModeManager           # Maneja matchmaking, spawns, Training/Versus
```

---

## Flujo de Ejecución

### 1. Inicio del Juego

```
Jugador entra → UIManager muestra menú principal
  ↓
Click "Training" → CharacterSelectComponent (modo dual: jugador + dummy)
  ↓
Confirmar selección → SetAttribute("SelectedCharacter", nombre)
                    → SetAttribute("SelectedDummyCharacter", dummyNombre)
  ↓
FireServer(StartTraining) → GameModeManager.StartTrainingMode()
  ↓
Asigna spawn, respawnea, notifica cliente con SetOpponent(dummy)
```

### 1.5 Sistema de Personajes

```
Characters/
  ├── BaseCharacter    → Info, Attacks, Commands, Skins, GetAnimationsFolder(), GetSkin()
  ├── CharacterRegistry → GetAll(), Get(name), GetAttacks(name), GetCommands(name)
  ├── Ryu/
  │   ├── Ryu.luau     → Info + Attacks + Commands + Skins
  │   └── Animations/Test/  → KeyframeSequences con sufijo _R/_L
  └── Ken/
      ├── Ken.luau     → Info + Attacks + Commands + Skins
      └── Animations/Test/  → KeyframeSequences con sufijo _R/_L

Flujo de selección (Versus — selección simple):
  UIManager → CharacterSelectComponent → Player:SetAttribute("SelectedCharacter")
  ↓
  InputClient lee atributo → CharacterController.new(char, machine, "Ryu")

Flujo de selección (Training — selección dual):
  UIManager → CharacterSelectComponent(dualSelect=true)
  ↓
  Player:SetAttribute("SelectedCharacter", playerChar)
  Player:SetAttribute("SelectedDummyCharacter", dummyChar)
  ↓
  InputClient → CharacterController (usa SelectedCharacter)
  InitializeDummy → DummyController (usa SelectedDummyCharacter)

Carga de animaciones:
  AnimationController.new(context) → lee context.characterName
    → resuelve Characters/<Name>/Animations/Test/
    → carga todas las KeyframeSequences con _R/_L
  
  LoadOpponentAnimations(char, opponentCharName)
    → resuelve carpeta de animaciones del oponente
    → para dummy: lee SelectedDummyCharacter
    → para jugador: lee su SelectedCharacter

Sistema de Skins:
  BaseCharacter:GetSkin(skinName)
    → Busca en Skins[skinName] → fallback Skins["Default"] → fallback "Dummy"
```

### 2. Inicialización del Personaje

```
InputClient.local.luau (CharacterScript):
  1. Crea InputBuffer (0.35s window)
  2. Crea StateMachine (estado inicial: "Idle")
  3. Crea CharacterController(character, machine)
     ├── AnimationController: carga todas las animaciones _R/_L
     ├── CharacterMotor: physics, movimiento, colisión
     └── CombatController: ataques, hit reactions, predicción
  4. Conecta InputBegan/InputEnded → comandos
  5. RenderStepped: CommandParser parsea buffer → RequestAttack
```

### 3. Loop Principal (cada RenderStepped)

```
CharacterController (RenderStepped):
  ├── StateMachine:Update()    → ejecuta Update() del estado actual
  ├── CombatController:Update() → opponent prediction, attackFrame count
  └── CharacterMotor:Update()   → physics + CFrame
       ├── Si hitstop → congela, lock plane
       ├── Si hit reaction (hitstun/knockdown/wakeup/blockstun)
       │   → solo lee root.Position.X (atacante tiene NetworkOwner)
       └── Si normal:
           ├── UpdateAirState()            → detecta despegue/aterrizaje
           ├── UpdateFacing()              → gira hacia oponente
           ├── UpdateWalkMovement(dt)      → aplica movimiento WASD
           ├── UpdatePushback()            → aplica velocidad de empuje con decay
           ├── UpdateDodge(dt)             → movimiento del dodge
           └── ApplyPlaneLockAndRotation() → escribe CFrame final (X,Y,Z lock)
```

### 4. Flujo de un Golpe (Hit)

```
Atacante presiona J/K → CommandParser detecta "Punch"/"HeavyPunch"
  ↓
CombatController:RequestAttack() → StateMachine → "Attack"
  ↓
task.delay(Startup) → Hitbox.new() → detecta HurtboxBody del oponente
  ↓
DamageService.ApplyHit() → FireServer("ApplyDamage")
  ↓
=== SERVIDOR (DamageHandler) ===
  ├── Valida distancia (X < 20, Y < 15)
  ├── Valida que sea oponente legítimo
  ├── Humanoid:TakeDamage()
  ├── Setea 14 atributos en el character de la víctima
  ├── FireClient a ambos jugadores
  └── NetworkOwnership: nil → atacante → (delay) → víctima
  ↓
=== CLIENTE ATACANTE ===
  └── _G.LocalHitPrediction → CombatController:ApplyLocalHitPrediction()
      ├── Hurtflash: pulso blanco/original en víctima durante hitstop
      ├── Hitstop: congela animaciones de ambos
      ├── Pushback predicho: mueve oponente visualmente
      └── Controla CFrame del oponente durante reacción
  ↓
=== CLIENTE VÍCTIMA ===
  └── GetAttributeChangedSignal("HitResultId") →
      CombatController:ProcessIncomingHit()
      ├── Motor cede CFrame (isInHitReaction = true, solo lee Position.X)
      ├── Hurtflash: pulso blanco/original durante hitstop
      ├── Hitstop → pushback post-hitstop
      └── task.delay(hitstunDuration) → sync currentX → sale de hitstun
```

### 5. NetworkOwnership durante un Hit

```
Estado normal:  Víctima tiene ownership de su propio personaje
  ↓
Hit confirmado: Server → SetNetworkOwner(nil) → SetNetworkOwner(atacante)
  ↓
Durante reacción: Atacante controla posición (predicción local)
                  Motor de víctima solo LEE root.Position.X
  ↓
Reacción termina: Server → SetNetworkOwner(víctima)
                  Motor de víctima sincroniza currentX = root.Position.X
                  Motor retoma control de CFrame
```

---

## Datos de Ataques (Attacks.luau)

| Ataque       | Startup | Active | Recovery | Damage | Pushback | Hitstop | Knockdown |
|-------------|---------|--------|----------|--------|----------|---------|-----------|
| Punch        | 4f      | 4f     | 10f      | 10     | 20       | 40f     | No        |
| HeavyPunch   | 12f     | 3f     | 16f      | 20     | 5.5      | 9f      | No        |
| CrouchPunch  | 5f      | 3f     | 10f      | 8      | 8        | 4f      | No        |
| CrouchHeavy  | 10f     | 4f     | 18f      | 15     | 6        | 7f      | Sí        |
| AirPunch     | 3f      | 5f     | 8f       | 8      | 4        | 4f      | No        |
| AirHeavy     | 8f      | 4f     | 14f      | 15     | 6        | 7f      | Sí        |

*f = frames a 60fps. Ejemplo: 40f = 0.667 segundos.*

---

## Fórmulas Clave

**Pushback velocity**: `direction * pushback * 0.12` studs/frame  
**Pushback decay**: `12%` de la velocidad por frame  
**Hitstop**: duración = `hitstopFrames / 60` segundos  
**Hurtflash**: pulso blanco/original cada 2 frames durante hitstop (VFXService.HurtFlash)  
**Duración reacción total**: `hitstop + hitstun + knockdown(0.8) + wakeup(0.4)`  
**Ownership return delay**: `totalReactionTime + 0.15s buffer`

---

## Sistemas Deshabilitados

- **Block/Guard**: Comentado en CharacterMotor y CombatController. Reemplazado por Dodge.
- **CharacterController_Legacy**: Versión monolítica anterior. No se usa.
- **DebugInputTest**: Script de debug comentado.

---

## Glosario

| Término | Significado |
|---------|-------------|
| **Hitstop** | Congelamiento mutuo al impactar (hitfreeze) |
| **Hurtflash** | Flash pulsante blanco/original en la víctima durante hitstop |
| **Hitstun** | Período post-hitstop donde la víctima no puede actuar |
| **Pushback** | Empuje horizontal aplicado al recibir un golpe |
| **Blockstun** | Hitstun al bloquear (menor duración) |
| **Knockdown** | Estado de caído al piso tras ciertos ataques |
| **Wakeup** | Animación de levantarse después de knockdown |
| **Juggle** | Combo aéreo (máximo 3 hits) |
| **NetworkOwnership** | Control de quién simula la física de un personaje |
| **currentX** | Posición horizontal local del motor (fuente de verdad para CFrame) |
| **Plane Lock** | Z y rotación forzados → movimiento solo en X |
