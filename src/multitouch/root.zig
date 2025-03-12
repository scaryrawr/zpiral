const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const assert = std.debug.assert;

extern fn CFRelease(device: *anyopaque) void;

pub const MTDimensions = extern struct {
    width: i32,
    height: i32,
};

pub const MtPoint = extern struct { x: f32, y: f32 };

pub const MtReadout = extern struct {
    point: MtPoint,
    velocity: MtPoint,
};

pub const Finger = extern struct {
    frame: i32,
    timestamp: f64,
    identifier: i32,
    state: i32,
    finger_number: i32,
    hand_id: i32,
    normalized: MtReadout,
    size: f32,
    pressure: i32,
    angle: f32,
    major_axis: f32,
    minor_axis: f32,
    absolute_vector: MtReadout,
    unknown: [2]i32,
    z_density: f32,
};

const MTAnyContactFrameCallback = struct {
    context: *anyopaque,
    callbackFn: *const fn (device: *MTDevice, fingers: [*c]Finger, count: i32, timestamp: f64, frame: i32, context: *anyopaque) callconv(.c) void,
};

pub fn GenericContactFrameCallback(comptime Context: type, comptime callbackFn: fn (context: Context, device: *MTDevice, fingers: []Finger, timestamp: f64, frame: i32) void) type {
    return struct {
        context: Context,
        const Self = @This();

        pub inline fn any(self: *Self) MTAnyContactFrameCallback {
            return .{ .context = @ptrCast(&self.context), .callbackFn = callback };
        }

        pub fn callback(device: *MTDevice, fingers: [*c]Finger, count: i32, timestamp: f64, frame: i32, context: *anyopaque) callconv(.c) void {
            const ptr: *Context = @alignCast(@ptrCast(context));
            return callbackFn(ptr.*, device, fingers[0..@as(usize, @intCast(count))], timestamp, frame);
        }
    };
}

pub const MTContactFrameCallback = GenericContactFrameCallback;

pub const MTDevice = opaque {
    const Self = @This();

    pub fn init() Allocator.Error!*MTDevice {
        return MTDeviceCreateDefault() orelse error.OutOfMemory;
    }

    pub fn release(self: *Self) void {
        MTDeviceRelease(self);
    }

    pub fn isRunning(self: *Self) bool {
        return MTDeviceIsRunning(self);
    }

    pub fn start(self: *Self, mode: i32) bool {
        const result = MTDeviceStart(self, mode);
        return result == 0;
    }

    pub fn stop(self: *Self) void {
        MTDeviceStop(self);
    }

    pub fn registerContactFrameCallback(self: *Self, callback: MTAnyContactFrameCallback) bool {
        return MTRegisterContactFrameCallbackWithRefcon(self, callback.callbackFn, callback.context) != 0;
    }

    pub fn unregisterContactFrameCallback(self: *Self, callback: MTAnyContactFrameCallback) void {
        return MTUnregisterContactFrameCallback(self, callback.callbackFn);
    }

    pub fn getDimensions(self: *Self) MTDimensions {
        var width: i32 = 0;
        var height: i32 = 0;
        if (MTDeviceGetSensorSurfaceDimensions(self, &width, &height) != 0) {
            return MTDimensions{ .width = 0, .height = 0 }; // or some error case
        }

        return MTDimensions{ .width = width, .height = height };
    }

    extern fn MTDeviceGetSensorSurfaceDimensions(device: *MTDevice, width: *i32, height: *i32) i32;

    extern fn MTDeviceCreateDefault() ?*MTDevice;
    extern fn MTDeviceRelease(device: *MTDevice) void;
    extern fn MTDeviceStart(device: *MTDevice, mode: i32) i32;
    extern fn MTDeviceStop(device: *MTDevice) void;
    extern fn MTDeviceIsRunning(device: *MTDevice) bool;

    const ContactFrameCallbackFunction = *const fn (device: *MTDevice, fingers: [*c]Finger, count: i32, timestamp: f64, frame: i32, context: *anyopaque) callconv(.c) void;
    extern fn MTRegisterContactFrameCallback(device: *MTDevice, callback: ContactFrameCallbackFunction) i32;
    extern fn MTRegisterContactFrameCallbackWithRefcon(device: *MTDevice, callback: ContactFrameCallbackFunction, context: *anyopaque) i32;
    extern fn MTUnregisterContactFrameCallback(device: *MTDevice, callback: ContactFrameCallbackFunction) void;
};

pub const MTDeviceList = opaque {
    const Self = @This();
    pub fn init() Allocator.Error!*MTDeviceList {
        return MTDeviceCreateList() orelse error.OutOfMemory;
    }

    pub fn release(self: *Self) void {
        CFRelease(self);
    }

    pub fn count(self: *Self) usize {
        return CFArrayGetCount(self);
    }

    pub fn at(self: *Self, index: usize) *MTDevice {
        assert(index < self.count());
        return @ptrCast(@alignCast(CFArrayGetValueAtIndex(self, index)));
    }

    extern fn MTDeviceCreateList() ?*MTDeviceList;
    extern fn CFArrayGetCount(array: *anyopaque) usize;
    extern fn CFArrayGetValueAtIndex(array: *anyopaque, index: usize) *anyopaque;
};

test "should have devices" {
    const device_array = MTDeviceList.init() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return err;
    };
    defer device_array.release();

    try testing.expect(device_array.count() > 0);
}

test "should be able to start array device" {
    const device_array = MTDeviceList.init() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return err;
    };
    defer device_array.release();

    try testing.expect(device_array.count() > 0);

    const device = device_array.at(0);
    try testing.expect(device.start(0));
    errdefer device.stop();
    try testing.expect(device.isRunning());
    device.stop();
    try testing.expect(!device.isRunning());
}

test "should be able to start default device" {
    const device = MTDevice.init() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return err;
    };
    defer device.release();

    try testing.expect(device.start(0));
    errdefer device.stop();
    try testing.expect(device.isRunning());
    device.stop();
    try testing.expect(!device.isRunning());
}

test "should be able to register fancy callback" {
    const device = MTDevice.init() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return err;
    };
    defer device.release();

    const dummyCallback = struct {
        fn cb(_: void, _: *MTDevice, _: []Finger, _: f64, _: i32) void {
            // Dummy callback implementation
        }
    }.cb;

    const NullCallback = MTContactFrameCallback(void, dummyCallback);
    var null_callback: NullCallback = .{ .context = {} };

    try testing.expect(device.registerContactFrameCallback(null_callback.any()));
    defer device.unregisterContactFrameCallback(null_callback.any());
}
