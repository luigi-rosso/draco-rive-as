// Ported from draco.js core/Status.js (status.h/cc).

export enum StatusCode {
    OK = 0,
    DRACO_ERROR = -1,
    IO_ERROR = -2,
    INVALID_PARAMETER = -3,
    UNSUPPORTED_VERSION = -4,
    UNKNOWN_VERSION = -5,
    UNSUPPORTED_FEATURE = -6,
}

export class Status {
    code: i32;
    errorMsg: string;

    constructor(code: i32 = StatusCode.OK, errorMsg: string = "") {
        this.code = code;
        this.errorMsg = errorMsg;
    }

    ok(): bool {
        return this.code == StatusCode.OK;
    }
}

export function okStatus(): Status {
    return new Status(StatusCode.OK);
}
