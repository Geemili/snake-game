const math = @import("std").math;

pub const Color = struct { r: u8, g: u8, b: u8 };
pub const Vec2 = struct { x: i32, y: i32 };
pub const Vec2f = struct {
    x: f32,
    y: f32,

    pub fn fromVeci(veci: Vec2) Vec2f {
        return .{
            .x = @intToFloat(f32, veci.x),
            .y = @intToFloat(f32, veci.y),
        };
    }

    pub fn unitFromRad(radians: f32) Vec2f {
        return .{
            .x = math.cos(radians),
            .y = math.sin(radians),
        };
    }

    pub fn scalMul(self: Vec2f, scal: f32) Vec2f {
        return Vec2f{
            .x = self.x * scal,
            .y = self.y * scal,
        };
    }

    pub fn dot(self: Vec2f, other: Vec2f) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn mul(self: Vec2f, other: Vec2f) Vec2f {
        return .{
            .x = self.x * other.x,
            .y = self.y * other.y,
        };
    }

    pub fn add(self: Vec2f, other: Vec2f) Vec2f {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn sub(self: Vec2f, other: Vec2f) Vec2f {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub fn normalize(self: Vec2f) Vec2f {
        const mag = self.magnitude();
        return Vec2f{
            .x = self.x / mag,
            .y = self.y / mag,
        };
    }

    pub fn magnitude(self: Vec2f) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn rotate(self: Vec2f, radians: f32) Vec2f {
        return .{
            .x = self.x * math.cos(radians) - self.y * math.sin(radians),
            .y = self.y * math.cos(radians) + self.x * math.sin(radians),
        };
    }
};
pub const Rect = struct { x: i32, y: i32, w: i32, h: i32 };
pub const Rect2f = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn translate(self: Rect2f, vector: Vec2f) Rect2f {
        return .{
            .x = self.x + vector.x,
            .y = self.y + vector.y,
            .w = self.w,
            .h = self.h,
        };
    }

    pub fn contains(self: Rect2f, point: Vec2f) bool {
        return point.x > self.x - self.w / 2 and point.x < self.x + self.w / 2 and point.y > self.y - self.h / 2 and point.y < self.y + self.h / 2;
    }

    pub fn top_left(self: Rect2f) Vec2f {
        return Vec2f{ .x = -self.w / 2 + self.x, .y = -self.h / 2 + self.y };
    }

    pub fn top_right(self: Rect2f) Vec2f {
        return Vec2f{ .x = self.w / 2 + self.x, .y = -self.h / 2 + self.y };
    }

    pub fn bottom_left(self: Rect2f) Vec2f {
        return Vec2f{ .x = -self.w / 2 + self.x, .y = self.h / 2 + self.y };
    }

    pub fn bottom_right(self: Rect2f) Vec2f {
        return Vec2f{ .x = self.w / 2 + self.x, .y = self.h / 2 + self.y };
    }
};

pub const EventTag = enum {
    Quit,

    ScreenResized,

    KeyDown,
    KeyUp,
    TextEditing,
    TextInput,

    MouseMotion,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,

    Custom,
};

pub const Event = union(enum) {
    Quit: void,

    ScreenResized: Vec2,

    KeyDown: KeyEvent,
    KeyUp: KeyEvent,
    TextEditing: void,
    TextInput: void,

    MouseMotion: Vec2,
    MouseButtonDown: MouseButtonEvent,
    MouseButtonUp: MouseButtonEvent,
    MouseWheel: Vec2,

    Custom: u32,
};

pub const KeyEvent = struct {
    scancode: Scancode,
};

pub const MouseButton = enum {
    Left,
    Middle,
    Right,
    X1,
    X2,
};

pub const MouseButtonEvent = struct { pos: Vec2, button: MouseButton };

pub const Scancode = enum(u16) {
    UNKNOWN,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    _1,
    _2,
    _3,
    _4,
    _5,
    _6,
    _7,
    _8,
    _9,
    _0,
    RETURN,
    ESCAPE,
    BACKSPACE,
    TAB,
    SPACE,
    MINUS,
    EQUALS,
    LEFTBRACKET,
    RIGHTBRACKET,
    BACKSLASH,
    NONUSHASH,
    SEMICOLON,
    APOSTROPHE,
    GRAVE,
    COMMA,
    PERIOD,
    SLASH,
    CAPSLOCK,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    PRINTSCREEN,
    SCROLLLOCK,
    PAUSE,
    INSERT,
    HOME,
    PAGEUP,
    DELETE,
    END,
    PAGEDOWN,
    RIGHT,
    LEFT,
    DOWN,
    UP,
    NUMLOCKCLEAR,
    KP_DIVIDE,
    KP_MULTIPLY,
    KP_MINUS,
    KP_PLUS,
    KP_ENTER,
    KP_1,
    KP_2,
    KP_3,
    KP_4,
    KP_5,
    KP_6,
    KP_7,
    KP_8,
    KP_9,
    KP_0,
    KP_PERIOD,
    NONUSBACKSLASH,
    APPLICATION,
    POWER,
    KP_EQUALS,
    F13,
    F14,
    F15,
    F16,
    F17,
    F18,
    F19,
    F20,
    F21,
    F22,
    F23,
    F24,
    EXECUTE,
    HELP,
    MENU,
    SELECT,
    STOP,
    AGAIN,
    UNDO,
    CUT,
    COPY,
    PASTE,
    FIND,
    MUTE,
    VOLUMEUP,
    VOLUMEDOWN,
    KP_COMMA,
    KP_EQUALSAS400,
    INTERNATIONAL1,
    INTERNATIONAL2,
    INTERNATIONAL3,
    INTERNATIONAL4,
    INTERNATIONAL5,
    INTERNATIONAL6,
    INTERNATIONAL7,
    INTERNATIONAL8,
    INTERNATIONAL9,
    LANG1,
    LANG2,
    LANG3,
    LANG4,
    LANG5,
    LANG6,
    LANG7,
    LANG8,
    LANG9,
    ALTERASE,
    SYSREQ,
    CANCEL,
    CLEAR,
    PRIOR,
    RETURN2,
    SEPARATOR,
    OUT,
    OPER,
    CLEARAGAIN,
    CRSEL,
    EXSEL,
    KP_00,
    KP_000,
    THOUSANDSSEPARATOR,
    DECIMALSEPARATOR,
    CURRENCYUNIT,
    CURRENCYSUBUNIT,
    KP_LEFTPAREN,
    KP_RIGHTPAREN,
    KP_LEFTBRACE,
    KP_RIGHTBRACE,
    KP_TAB,
    KP_BACKSPACE,
    KP_A,
    KP_B,
    KP_C,
    KP_D,
    KP_E,
    KP_F,
    KP_XOR,
    KP_POWER,
    KP_PERCENT,
    KP_LESS,
    KP_GREATER,
    KP_AMPERSAND,
    KP_DBLAMPERSAND,
    KP_VERTICALBAR,
    KP_DBLVERTICALBAR,
    KP_COLON,
    KP_HASH,
    KP_SPACE,
    KP_AT,
    KP_EXCLAM,
    KP_MEMSTORE,
    KP_MEMRECALL,
    KP_MEMCLEAR,
    KP_MEMADD,
    KP_MEMSUBTRACT,
    KP_MEMMULTIPLY,
    KP_MEMDIVIDE,
    KP_PLUSMINUS,
    KP_CLEAR,
    KP_CLEARENTRY,
    KP_BINARY,
    KP_OCTAL,
    KP_DECIMAL,
    KP_HEXADECIMAL,
    LCTRL,
    LSHIFT,
    LALT,
    LGUI,
    RCTRL,
    RSHIFT,
    RALT,
    RGUI,
    MODE,
    AUDIONEXT,
    AUDIOPREV,
    AUDIOSTOP,
    AUDIOPLAY,
    AUDIOMUTE,
    MEDIASELECT,
    WWW,
    MAIL,
    CALCULATOR,
    COMPUTER,
    AC_SEARCH,
    AC_HOME,
    AC_BACK,
    AC_FORWARD,
    AC_STOP,
    AC_REFRESH,
    AC_BOOKMARKS,
    BRIGHTNESSDOWN,
    BRIGHTNESSUP,
    DISPLAYSWITCH,
    KBDILLUMTOGGLE,
    KBDILLUMDOWN,
    KBDILLUMUP,
    EJECT,
    SLEEP,
    APP1,
    APP2,
};
