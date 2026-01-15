-- Background music module
-- Manages playlist of tracks, loops through them independently of game state

local music = {}

-- Playlist of tracks (loaded in init)
local tracks = {}
local currentTrack = 1
local enabled = true

-- Track file paths (relative to game folder)
local trackFiles = {
    "assets/music/01-a-night-of-dizzy-spells.mp3",
    "assets/music/02-underclocked.mp3",
    "assets/music/03-chibi-ninja.mp3",
    "assets/music/04-all-of-us.mp3",
    "assets/music/05-come-and-find-me.mp3",
    "assets/music/06-searching.mp3",
    "assets/music/07-were-the-resistors.mp3",
    "assets/music/08-ascending.mp3",
}

-- Initialize the music system (call from love.load)
function music.init()
    for i, path in ipairs(trackFiles) do
        local source = love.audio.newSource(path, "stream")
        source:setVolume(0.5)
        tracks[i] = source
    end
end

-- Start playing from current track
function music.play()
    if not enabled or #tracks == 0 then return end

    local track = tracks[currentTrack]
    if track and not track:isPlaying() then
        track:play()
    end
end

-- Stop all music
function music.stop()
    for _, track in ipairs(tracks) do
        track:stop()
    end
end

-- Pause current track
function music.pause()
    local track = tracks[currentTrack]
    if track then
        track:pause()
    end
end

-- Resume current track
function music.resume()
    if not enabled then return end
    local track = tracks[currentTrack]
    if track then
        track:play()
    end
end

-- Update (call from love.update to check for track end and advance)
function music.update()
    if not enabled or #tracks == 0 then return end

    local track = tracks[currentTrack]
    if track and not track:isPlaying() then
        -- Current track finished, advance to next
        currentTrack = currentTrack + 1
        if currentTrack > #tracks then
            currentTrack = 1  -- Loop back to beginning
        end
        tracks[currentTrack]:play()
    end
end

-- Enable/disable music
function music.setEnabled(value)
    enabled = value
    if enabled then
        music.play()
    else
        music.stop()
    end
end

function music.isEnabled()
    return enabled
end

-- Toggle music on/off
function music.toggle()
    music.setEnabled(not enabled)
    return enabled
end

-- Set volume (0.0 to 1.0)
function music.setVolume(vol)
    for _, track in ipairs(tracks) do
        track:setVolume(vol)
    end
end

return music
