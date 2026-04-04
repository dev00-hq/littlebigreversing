pub const WorldPointSnapshot = struct {
    x: i32,
    y: i32,
    z: i32,
};

pub const WorldBounds = struct {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,

    pub fn init(x: i32, z: i32) WorldBounds {
        return .{
            .min_x = x,
            .max_x = x,
            .min_z = z,
            .max_z = z,
        };
    }

    pub fn include(self: *WorldBounds, x: i32, z: i32) void {
        self.min_x = @min(self.min_x, x);
        self.max_x = @max(self.max_x, x);
        self.min_z = @min(self.min_z, z);
        self.max_z = @max(self.max_z, z);
    }

    pub fn spanX(self: WorldBounds) i32 {
        return @max(1, self.max_x - self.min_x);
    }

    pub fn spanZ(self: WorldBounds) i32 {
        return @max(1, self.max_z - self.min_z);
    }
};
