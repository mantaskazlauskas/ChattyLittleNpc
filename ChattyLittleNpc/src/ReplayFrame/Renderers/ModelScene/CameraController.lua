local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.CameraController = NS.CameraController or {}

function NS.CameraController.setOrientation(frame, rx, ry, rz, ux, uy, uz, fx, fy, fz)
    if not (frame and frame.SetCameraOrientationByAxisVectors) then return end
    -- Right, Up, Forward (Blizzard order)
    pcall(frame.SetCameraOrientationByAxisVectors, frame, rx, ry, rz, ux, uy, uz, fx, fy, fz)
end

function NS.CameraController.setNearClip(frame, nearClip)
    if frame and frame.SetCameraNearClip then
        pcall(frame.SetCameraNearClip, frame, tonumber(nearClip) or 0.05)
    end
end
