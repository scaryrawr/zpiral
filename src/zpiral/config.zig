const std = @import("std");
const toml = @import("toml");

pub const TouchEvent = struct {
    pub const Direction = enum {
        Up,
        Down,
        Left,
        Right,
    };
    num_fingers: u32,
    direction: Direction,
    command: []const u8,
};

pub const Config = struct {
    events: []const TouchEvent,
};

fn getConfigHome(allocator: std.mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const config_home = env_map.get("XDG_CONFIG_HOME") orelse "~/.config";
    if (config_home[0] == '~') {
        if (env_map.get("HOME")) |home| {
            const config_home_replace = try allocator.alloc(u8, config_home.len + home.len - 1);
            errdefer allocator.free(config_home_replace);

            std.mem.copyForwards(u8, config_home_replace, home);
            std.mem.copyForwards(u8, config_home_replace[home.len..], config_home[1..]);
            return config_home_replace;
        }
    }

    return try allocator.dupe(u8, config_home);
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const config_home = try getConfigHome(allocator);
    defer allocator.free(config_home);

    const sub_path = "/zpiral/zpiral.toml";
    const config_path = try allocator.alloc(u8, config_home.len + sub_path.len);
    errdefer allocator.free(config_path);

    std.mem.copyForwards(u8, config_path, config_home);
    std.mem.copyForwards(u8, config_path[config_home.len..], sub_path);

    return config_path;
}

fn loadConfig(allocator: std.mem.Allocator, config_str: []const u8) !toml.Parsed(Config) {
    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    return try parser.parseString(config_str);
}

pub fn loadConfigFile(allocator: std.mem.Allocator) !toml.Parsed(Config) {
    const filename = try getConfigPath(allocator);
    defer allocator.free(filename);

    const real_path = try std.fs.realpathAlloc(allocator, filename);
    defer allocator.free(real_path);

    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    return try parser.parseFile(real_path);
}

test "should be able to get a config path" {
    const allocator = std.testing.allocator;
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    // std.debug.print("Config path: {s}\n", .{config_path});
    try std.testing.expectStringEndsWith(config_path, "/.config/zpiral/zpiral.toml");
}

test "should parse single event" {
    const config_str =
        \\[[events]]
        \\num_fingers = 2
        \\direction = 'Up'
        \\command = 'echo Up'
    ;
    const config = try loadConfig(std.testing.allocator, config_str);
    defer config.deinit();

    const events = config.value;
    try std.testing.expect(events.events.len == 1);
    try std.testing.expect(events.events[0].num_fingers == 2);
    try std.testing.expect(events.events[0].direction == TouchEvent.Direction.Up);
}

test "should parse multiple event" {
    const config_str =
        \\[[events]]
        \\num_fingers = 2
        \\direction = 'Up'
        \\command = 'echo Up'
        \\
        \\[[events]]
        \\num_fingers = 3
        \\direction = 'Left'
        \\command = 'echo Left'
    ;

    const config = try loadConfig(std.testing.allocator, config_str);
    defer config.deinit();

    const events = config.value;
    try std.testing.expect(events.events.len == 2);
    try std.testing.expect(events.events[0].num_fingers == 2);
    try std.testing.expect(events.events[0].direction == TouchEvent.Direction.Up);
    try std.testing.expect(events.events[1].num_fingers == 3);
    try std.testing.expect(events.events[1].direction == TouchEvent.Direction.Left);
}
