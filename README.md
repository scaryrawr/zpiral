# zpiral

Multi-touch gesture tool. Based on [aerospace-swipe](https://github.com/acsandmann/aerospace-swipe), but with a configuration to run custom scripts.

Work in progress.

## Configuration

The configuration is a TOML file that defaults to `$XDG_CONFIG_HOME/.config/zpiral/zpiral.toml` and falls back to `~/.config/zpiral/zpiral.toml`.

It is an array of "events".

You register a script/command to be ran when a gesture is detected.

```zig
pub const TouchEvent = struct {
    pub const Gesture = enum {
        SwipeUp,
        SwipeDown,
        SwipeLeft,
        SwipeRight,
    };
    /// Number of fingers required in the gesture
    num_fingers: u32,
    /// Gesture to trigger the command.
    gesture: Gesture,
    /// Command to run when the event is triggered.
    command: []const u8,
    /// Threshold size for finger to be considered.
    finger_size_threshold: ?f32,
    /// The cooldown time in seconds for event to trigger again
    cooldown: ?f64,
};

pub const Config = struct {
    events: []const TouchEvent,
};
```

### Aerospace Example

This is what I'm using for 3 finger swipe left/right to switch workspaces in [aerospace](https://github.com/nikitabobko/AeroSpace).

```toml
[[events]]
num_fingers = 3
gesture = 'SwipeLeft'
command = 'aerospace workspace --wrap-around next'

[[events]]
num_fingers = 3
gesture = 'SwipeRight'
command = 'aerospace workspace --wrap-around prev'
```
