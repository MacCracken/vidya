// Vidya — Module Systems in TypeScript
//
// TypeScript uses ES modules (ESM) as its primary module system.
// Every file is a module if it has an import or export statement.
// The compiler resolves modules at compile time and erases type-only
// imports. At runtime, the JS engine (Node.js, browser) handles loading.
//
// Compare to Rust:
//   Rust mod/use     → TS import/export
//   Rust pub         → TS export (default is private to file)
//   Rust crate root  → TS barrel file (index.ts)
//   Rust pub(crate)  → TS has no equivalent (no crate-level visibility)
//   Rust mod.rs      → TS index.ts in a directory

// ── Named exports: the default pattern ────────────────────────────
// Every exported item is explicitly named. Consumers import by name.
// Like Rust's pub fn, pub struct, pub enum.

export function add(a: number, b: number): number {
    return a + b;
}

export function multiply(a: number, b: number): number {
    return a * b;
}

export const PI = 3.14159265358979;

export interface Vector2D {
    x: number;
    y: number;
}

// ── Default exports ───────────────────────────────────────────────
// One per module. Consumer can name it anything on import.
// Rust has no equivalent — every public item has a fixed name.
//
// BEST PRACTICE: Prefer named exports over default exports.
// Named exports enable auto-import, tree-shaking, and refactoring.
//
// export default class Calculator { ... }
// import Calc from "./calculator"; // consumer picks the name

// ── Re-exports: building a public facade ──────────────────────────
// Like Rust's pub use — expose items from submodules through a
// parent module. This decouples internal structure from public API.
//
// Barrel file pattern (index.ts):
// export { UserService } from "./user-service";
// export { AuthService } from "./auth-service";
// export type { User, Session } from "./types";
//
// Consumer imports from the barrel:
// import { UserService, AuthService } from "./services";

// ── Type-only imports: erased at compile time ─────────────────────
// TypeScript can import types that exist only at compile time.
// These are completely removed from the JS output.
//
// import type { User } from "./types";
// import { type User, createUser } from "./users";
//
// Rust equivalent: use crate::types::User (types are always zero-cost)

// ── Namespace: TypeScript's legacy module system ──────────────────
// Before ESM, TypeScript used namespaces (formerly "internal modules").
// Still useful for grouping related types without a separate file.

namespace MathUtils {
    export function clamp(value: number, min: number, max: number): number {
        return Math.max(min, Math.min(max, value));
    }

    export function lerp(a: number, b: number, t: number): number {
        return a + (b - a) * t;
    }

    // Not exported — private to the namespace
    function validateRange(min: number, max: number): boolean {
        return min <= max;
    }

    // Nested namespace
    export namespace Trig {
        export function degreesToRadians(degrees: number): number {
            return degrees * (Math.PI / 180);
        }
    }
}

// ── Declaration merging with namespaces ────────────────────────────
// Namespaces can merge with classes, functions, or enums to add
// static members. No Rust equivalent.

class Color {
    constructor(
        readonly r: number,
        readonly g: number,
        readonly b: number,
    ) {}

    toHex(): string {
        const hex = (n: number) => n.toString(16).padStart(2, "0");
        return `#${hex(this.r)}${hex(this.g)}${hex(this.b)}`;
    }
}

// Merge namespace into class — adds static "constants"
// eslint-disable-next-line @typescript-eslint/no-namespace
namespace Color {
    export const RED = new Color(255, 0, 0);
    export const GREEN = new Color(0, 255, 0);
    export const BLUE = new Color(0, 0, 255);
}

// ── Dynamic import: lazy loading ──────────────────────────────────
// import() returns a Promise — the module is loaded on demand.
// Useful for code splitting, conditional loading, and plugins.
//
// async function loadParser() {
//     const { parse } = await import("./parser");
//     return parse(input);
// }
//
// Rust equivalent: none directly (Rust links at compile time).
// dlopen/libloading is the closest for dynamic loading.

// ── Path mapping: module resolution configuration ─────────────────
// tsconfig.json paths map import specifiers to filesystem locations.
// Like Rust's [dependencies] in Cargo.toml + use statements.
//
// {
//   "compilerOptions": {
//     "paths": {
//       "@app/*": ["./src/*"],
//       "@shared/*": ["./shared/*"]
//     }
//   }
// }
//
// import { Logger } from "@app/logging";
// // resolves to ./src/logging

// ── Declaration files (.d.ts): type-only module interface ─────────
// .d.ts files describe the shape of a JS module without implementation.
// Like Rust's trait definitions or C header files.
//
// // math.d.ts
// declare function add(a: number, b: number): number;
// declare const PI: number;
// declare interface Vector2D { x: number; y: number; }
//
// Consumers get type checking without access to the source.
// The TypeScript compiler generates .d.ts from .ts files automatically.

// ── Ambient declarations: typing untyped JS ───────────────────────
// declare tells TypeScript about values that exist at runtime but
// have no TypeScript source. Used in .d.ts files and for globals.

declare const __VERSION__: string; // provided by bundler at build time
// Using __VERSION__ in code: TypeScript trusts the declaration

// ── Module patterns and anti-patterns ─────────────────────────────

// GOOD: One concern per module, named exports
// math.ts: export function add() { ... }
// strings.ts: export function capitalize() { ... }

// BAD: God module with everything
// utils.ts: export function add() { ... } export function capitalize() { ... }
//           export function parseDate() { ... } export function hash() { ... }

// GOOD: Barrel file re-exports a curated public API
// index.ts: export { add, multiply } from "./math";
//           export type { Vector2D } from "./types";

// BAD: Barrel re-exports everything (like Rust's pub use internal::*)
// index.ts: export * from "./math";
//           export * from "./strings";
//           export * from "./internal"; // accidentally publishes internals

// ── Circular dependency detection ─────────────────────────────────
// TypeScript allows circular imports, but they cause runtime issues:
// the imported module may be partially initialized.
//
// // a.ts: import { b } from "./b"; export const a = b + 1;
// // b.ts: import { a } from "./a"; export const b = a + 1;
// // Result: one of them gets undefined (partially initialized)
//
// Fix: extract shared code into a third module (break the cycle)
// Rust prevents this entirely: circular mod dependencies are a compiler error

// ── Simulated module system for testing ───────────────────────────

interface Module {
    name: string;
    exports: string[];
    imports: { from: string; names: string[] }[];
}

class ModuleRegistry {
    private modules = new Map<string, Module>();

    register(mod: Module): void {
        this.modules.set(mod.name, mod);
    }

    resolve(moduleName: string, exportName: string): boolean {
        const mod = this.modules.get(moduleName);
        if (!mod) return false;
        return mod.exports.includes(exportName);
    }

    detectCycles(): string[][] {
        const cycles: string[][] = [];
        const visited = new Set<string>();
        const stack = new Set<string>();

        const dfs = (name: string, path: string[]): void => {
            if (stack.has(name)) {
                const cycleStart = path.indexOf(name);
                cycles.push(path.slice(cycleStart).concat(name));
                return;
            }
            if (visited.has(name)) return;
            visited.add(name);
            stack.add(name);
            path.push(name);

            const mod = this.modules.get(name);
            if (mod) {
                for (const imp of mod.imports) {
                    dfs(imp.from, [...path]);
                }
            }

            stack.delete(name);
        };

        for (const name of this.modules.keys()) {
            dfs(name, []);
        }
        return cycles;
    }

    dependencyOrder(): string[] {
        const order: string[] = [];
        const visited = new Set<string>();

        const visit = (name: string): void => {
            if (visited.has(name)) return;
            visited.add(name);
            const mod = this.modules.get(name);
            if (mod) {
                for (const imp of mod.imports) {
                    visit(imp.from);
                }
            }
            order.push(name);
        };

        for (const name of this.modules.keys()) {
            visit(name);
        }
        return order;
    }
}

// ── Tests ─────────────────────────────────────────────────────────

function main(): void {
    // ── Named exports ─────────────────────────────────────────────
    assert(add(2, 3) === 5, "named export: add");
    assert(multiply(3, 4) === 12, "named export: multiply");
    assert(PI > 3.14 && PI < 3.15, "named export: PI");

    // ── Interface export ──────────────────────────────────────────
    const v: Vector2D = { x: 1, y: 2 };
    assert(v.x === 1 && v.y === 2, "exported interface");

    // ── Namespace ─────────────────────────────────────────────────
    assert(MathUtils.clamp(15, 0, 10) === 10, "namespace clamp high");
    assert(MathUtils.clamp(-5, 0, 10) === 0, "namespace clamp low");
    assert(MathUtils.clamp(5, 0, 10) === 5, "namespace clamp mid");
    assert(MathUtils.lerp(0, 100, 0.5) === 50, "namespace lerp");
    assert(MathUtils.lerp(0, 100, 0.25) === 25, "namespace lerp quarter");

    // ── Nested namespace ──────────────────────────────────────────
    assertClose(
        MathUtils.Trig.degreesToRadians(180),
        Math.PI,
        0.0001,
        "nested namespace",
    );

    // ── Declaration merging (namespace + class) ───────────────────
    assert(Color.RED.r === 255, "merged namespace: RED");
    assert(Color.GREEN.g === 255, "merged namespace: GREEN");
    assert(Color.BLUE.b === 255, "merged namespace: BLUE");
    assert(Color.RED.toHex() === "#ff0000", "merged: method on static");

    const custom = new Color(128, 64, 32);
    assert(custom.toHex() === "#804020", "class instance method");

    // ── Module registry: resolution ───────────────────────────────
    const registry = new ModuleRegistry();

    registry.register({
        name: "math",
        exports: ["add", "multiply", "PI"],
        imports: [],
    });

    registry.register({
        name: "geometry",
        exports: ["Circle", "Rectangle"],
        imports: [{ from: "math", names: ["PI", "multiply"] }],
    });

    registry.register({
        name: "app",
        exports: ["main"],
        imports: [
            { from: "math", names: ["add"] },
            { from: "geometry", names: ["Circle"] },
        ],
    });

    assert(registry.resolve("math", "add") === true, "resolve: exists");
    assert(registry.resolve("math", "subtract") === false, "resolve: missing");
    assert(registry.resolve("unknown", "add") === false, "resolve: no module");

    // ── Module registry: dependency order ─────────────────────────
    const order = registry.dependencyOrder();
    assert(order.indexOf("math") < order.indexOf("geometry"), "math before geometry");
    assert(order.indexOf("geometry") < order.indexOf("app"), "geometry before app");
    assert(order.indexOf("math") < order.indexOf("app"), "math before app");

    // ── Module registry: cycle detection ──────────────────────────
    const cycleRegistry = new ModuleRegistry();
    cycleRegistry.register({
        name: "a",
        exports: ["x"],
        imports: [{ from: "b", names: ["y"] }],
    });
    cycleRegistry.register({
        name: "b",
        exports: ["y"],
        imports: [{ from: "a", names: ["x"] }],
    });

    const cycles = cycleRegistry.detectCycles();
    assert(cycles.length > 0, "cycle detected");
    assert(cycles[0].includes("a") && cycles[0].includes("b"), "cycle contains a and b");

    // No cycles in the first registry
    const noCycles = registry.detectCycles();
    assert(noCycles.length === 0, "no cycles in DAG");

    // ── Key differences from Rust modules ─────────────────────────
    // 1. TS modules are file-based (one file = one module)
    //    Rust modules are declared with mod and can be inline
    // 2. TS has no pub(crate) — exports are all-or-nothing per item
    //    Rust has pub, pub(crate), pub(super), pub(in path)
    // 3. TS allows circular imports (runtime risk)
    //    Rust forbids circular mod dependencies (compile error)
    // 4. TS type-only imports are erased — zero cost at runtime
    //    Rust use is always zero-cost (all resolved at compile time)
    // 5. TS barrel files are convention; Rust lib.rs is the crate root

    console.log("All module system examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function assertClose(got: number, expected: number, tolerance: number, msg: string): void {
    assert(Math.abs(got - expected) < tolerance, `${msg}: got ${got}, expected ~${expected}`);
}

main();
