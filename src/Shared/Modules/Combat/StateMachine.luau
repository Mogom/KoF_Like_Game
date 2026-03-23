--[[
	StateMachine.lua
	----------------
	Máquina de estados simple y eficiente para controlar el estado
	del personaje en sistemas de combate o movimiento.

	Cada estado puede tener:
	Enter()  -> ejecutado al entrar al estado
	Update() -> ejecutado cada frame
	Exit()   -> ejecutado al salir del estado
]]

local StateMachine = {}
StateMachine.__index = StateMachine


-- Constructor
function StateMachine.new(initialState)

	local self = setmetatable({}, StateMachine)

	self.currentState = initialState
	self.states = {}

	return self

end


-- Registrar un nuevo estado
function StateMachine:AddState(name, stateData)

	self.states[name] = stateData

end


-- Cambiar de estado
function StateMachine:SetState(newState)

	if self.currentState == newState then
		return
	end

	local current = self.states[self.currentState]

	if current and current.Exit then
		current.Exit()
	end

	self.currentState = newState

	local nextState = self.states[newState]

	if nextState and nextState.Enter then
		nextState.Enter()
	end

end


-- Actualizar estado actual
function StateMachine:Update(dt)

	local state = self.states[self.currentState]

	if state and state.Update then
		state.Update(dt)
	end

end


-- Obtener estado actual
function StateMachine:GetState()

	return self.currentState

end


return StateMachine