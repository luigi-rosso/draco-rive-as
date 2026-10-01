// Ported from draco.js compression/config/DracoOptions.js.
// Global options plus per-attribute options keyed by attribute key. Only the
// bool getters exist on the decode path, so values are typed bool.

export class DracoOptions {
    globalOptions: Map<string, bool> = new Map<string, bool>();
    attributeOptions: Map<i32, Map<string, bool>> = new Map<i32, Map<string, bool>>();

    getGlobalBool(name: string, defaultVal: bool): bool {
        if (this.globalOptions.has(name)) {
            return this.globalOptions.get(name);
        }
        return defaultVal;
    }

    findAttributeOptions(attKey: i32): Map<string, bool>? {
        if (this.attributeOptions.has(attKey)) {
            return this.attributeOptions.get(attKey);
        }
        return null;
    }

    getAttributeBool(attKey: i32, name: string, defaultVal: bool): bool {
        let attOpts = this.findAttributeOptions(attKey);
        if (attOpts != null && attOpts.has(name)) {
            return attOpts.get(name);
        }
        return this.getGlobalBool(name, defaultVal);
    }
}
