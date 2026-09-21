extends SceneTree
var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var stage := ""
func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		var json := FileAccess.get_file_as_string(stage.path_join("crudespoon.json"))
		world.add_model("ReplicatedStorage/OnChain", "Spoonie", json)
		world.run_chunk("wear", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local src = rs:WaitForChild("OnChain", 2):FindFirstChild("Spoonie")
local ch = Players:GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local c = src:Clone(); c.Parent = ch; hum:AddAccessory(c)
""")
	elif phase == 1 and t > 6.0:
		phase = 2
		world.run_chunk("axes", """
local Players = game:GetService("Players")
local ch = Players:GetPlayers()[1].Character
local torso = ch:FindFirstChild("Torso")
local arm = ch:FindFirstChild("Right Arm")
local function p(v) return ("%.2f,%.2f,%.2f"):format(v.X, v.Y, v.Z) end
print("TORSO " .. p(torso.Position))
print("RARM  " .. p(arm.Position))
print("OUT   " .. p((arm.Position - torso.Position).Unit))
for _, acc in ipairs(ch:GetChildren()) do
    if acc:IsA("Accoutrement") and acc.Name == "Spoonie" then
        for _, part in ipairs(acc:GetChildren()) do
            if part:IsA("BasePart") then
                local rel = part.Position - arm.Position
                print(("PART %s at %s  rel-to-arm %s"):format(part.Name, p(part.Position), p(rel)))
            end
        end
    end
end
""")
	elif phase == 2 and t > 8.0:
		quit(0)
	return false
