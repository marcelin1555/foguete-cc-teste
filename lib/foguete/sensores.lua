-- lib/foguete/sensores.lua : leitura da nave (CC: Sable) e gravidade
local mat = require("foguete.mat")
local M = {}

-- as 4 leituras em paralelo: cada uma pode custar 1 tick se feita em sequencia
function M.readShip()
  local pose, vel, angv, mass
  parallel.waitForAll(
    function() pose = sublevel.getLogicalPose() end,
    function() vel = sublevel.getVelocity() end,
    function() angv = sublevel.getAngularVelocity() end,
    function() mass = sublevel.getMass() end)
  return {
    pos = pose.position,
    q = mat.quatParts(pose.orientation),
    vel = vel,
    angv = angv,
    mass = mass,
  }
end

function M.gravity()
  local ok, g = pcall(aero.getGravity)
  if ok and g and g:length() > 0.01 then return g:length() end
  return 9.81
end

return M
