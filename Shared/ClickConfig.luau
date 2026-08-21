local ClickConfig = {}

ClickConfig.StepsPerSecond = 6 -- amount of speed gains per second of walking
ClickConfig.MinTickStuds = 0.5 -- must move at least this far in a tick to count as walking
ClickConfig.MaxTickStuds = 150 -- more than this in one tick is a teleport, not movement

return ClickConfig