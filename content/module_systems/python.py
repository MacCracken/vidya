# Vidya — Module Systems in Python
#
# Python's module system maps files to namespaces:
#   - A .py file IS a module
#   - A directory with __init__.py IS a package
#   - import loads and caches modules (sys.modules)
#   - __all__ controls what `from module import *` exports
#   - Relative imports (from . import x) work within packages
#
# Compared to Rust:
#   Python module   ≈ Rust mod (one file = one module)
#   Python package  ≈ Rust mod with submodules (directory)
#   __all__         ≈ pub (visibility control for wildcard imports)
#   import          ≈ use (bring names into scope)
#   sys.modules     ≈ (no equivalent — Rust links at compile time)

import sys
import importlib
import types


def main():
    # ── Module basics: every .py file is a module ──────────────────
    # When you `import math`, Python:
    #   1. Checks sys.modules (cache) — return if already loaded
    #   2. Finds the file on sys.path
    #   3. Creates a new module object
    #   4. Executes the file's code in the module's namespace
    #   5. Stores it in sys.modules
    #   6. Binds the name in the importer's namespace

    import math
    assert math.pi > 3.14
    assert "math" in sys.modules

    # Module attributes are just the module's global variables
    assert hasattr(math, "sqrt")
    assert hasattr(math, "pi")

    # ── Import forms ───────────────────────────────────────────────

    # import module — full qualified name required
    import os.path
    assert os.path.sep in ("/", "\\")

    # from module import name — brings name into local scope
    from collections import OrderedDict
    od = OrderedDict()
    od["a"] = 1
    assert list(od.keys()) == ["a"]

    # from module import name as alias — rename on import
    from datetime import datetime as dt
    assert hasattr(dt, "now")

    # ── __all__: controlling public API ────────────────────────────
    # __all__ defines what `from module import *` exports.
    # Without __all__, all names not starting with _ are exported.
    # This is Python's visibility control — like Rust's pub.

    # Simulate a module with __all__
    fake_module = types.ModuleType("fake_module")
    fake_module.public_func = lambda: "public"
    fake_module._private_func = lambda: "private"
    fake_module.also_public = lambda: "also public"
    fake_module.__all__ = ["public_func"]  # only this is exported by *

    # __all__ controls wildcard imports
    assert "public_func" in fake_module.__all__
    assert "also_public" not in fake_module.__all__
    assert "_private_func" not in fake_module.__all__

    # ── Package structure ──────────────────────────────────────────
    # A package is a directory with __init__.py:
    #
    #   mypackage/
    #   ├── __init__.py      # makes it a package; runs on import
    #   ├── core.py           # mypackage.core
    #   ├── utils.py          # mypackage.utils
    #   └── sub/
    #       ├── __init__.py   # mypackage.sub
    #       └── helpers.py    # mypackage.sub.helpers
    #
    # __init__.py typically:
    #   - Imports and re-exports public API (like Rust's pub use)
    #   - Sets __all__ to control wildcard exports
    #   - Initializes package-level state
    #
    # Example __init__.py:
    #   from .core import Engine, Config
    #   from .utils import helper
    #   __all__ = ["Engine", "Config", "helper"]

    # ── Relative imports ───────────────────────────────────────────
    # Inside a package, use relative imports:
    #   from . import sibling        # same directory
    #   from .sibling import func    # name from sibling
    #   from .. import parent        # parent package
    #   from ..other import thing    # sibling package
    #
    # Relative imports only work inside packages (not scripts).
    # They make packages relocatable — like Rust's crate:: prefix.

    # ── Namespace packages (PEP 420) ──────────────────────────────
    # Directories WITHOUT __init__.py can still be packages.
    # Multiple directories can contribute to the same namespace.
    # Used for plugin systems and split packages.
    #
    # Regular package: one directory, one __init__.py
    # Namespace package: multiple directories, no __init__.py

    # ── sys.path: where Python finds modules ──────────────────────
    # Python searches these directories in order:
    #   1. Directory of the script being run
    #   2. PYTHONPATH environment variable
    #   3. Standard library paths
    #   4. Site-packages (third-party)
    assert isinstance(sys.path, list)
    assert len(sys.path) > 0

    # ── Module as singleton ────────────────────────────────────────
    # Modules are cached in sys.modules. Importing twice returns
    # the SAME object. Module-level code runs only once.

    import json
    json_id1 = id(json)
    # Re-import — same object
    import json as json2
    assert id(json2) == json_id1  # same module object

    # ── Dynamic imports ────────────────────────────────────────────
    # importlib.import_module() imports by string name — useful for
    # plugin systems where module names come from configuration.

    math_module = importlib.import_module("math")
    assert math_module.sqrt(16) == 4.0
    assert math_module is math  # same cached module

    # ── Module attributes and introspection ────────────────────────
    # Every module has metadata attributes:
    #   __name__   — module name (or "__main__" for the entry point)
    #   __file__   — path to the .py file
    #   __doc__    — module docstring
    #   __package__— package name for relative imports

    assert math.__name__ == "math"
    assert hasattr(math, "__file__")

    # __name__ == "__main__" identifies the entry point script
    # This is why `if __name__ == "__main__":` works

    # ── Circular imports ───────────────────────────────────────────
    # Python allows circular imports but they can cause problems:
    #   module_a imports module_b, module_b imports module_a
    #
    # At import time, module_a is partially initialized when module_b
    # tries to use it. Solutions:
    #   1. Import at function level (lazy import)
    #   2. Restructure to remove the cycle
    #   3. Use TYPE_CHECKING guard for type hints only
    #
    # from typing import TYPE_CHECKING
    # if TYPE_CHECKING:
    #     from .other import SomeType  # only for type checkers

    # ── Visibility conventions ─────────────────────────────────────
    # Python has no enforced privacy. Conventions:
    #   public_name      — part of the API
    #   _private_name    — internal, not exported by import *
    #   __mangled_name   — name-mangled by the class (not truly private)
    #   __dunder__       — Python special methods

    class Example:
        def public_method(self):
            return "public"

        def _internal_method(self):
            return "internal"

        def __mangled_method(self):
            return "mangled"

    e = Example()
    assert e.public_method() == "public"
    assert e._internal_method() == "internal"  # accessible, but discouraged
    # Name mangling: __mangled becomes _Example__mangled
    assert e._Example__mangled_method() == "mangled"

    # ── Comparison with Rust module system ─────────────────────────
    # Rust:                          Python:
    #   mod foo;                       import foo
    #   pub fn                         __all__ or no _ prefix
    #   pub(crate)                     _ prefix convention
    #   pub(super)                     (no equivalent)
    #   use crate::foo::Bar           from .foo import Bar
    #   pub use (re-export)           __init__.py re-exports
    #   separate compilation          .pyc caching
    #   static linking                sys.modules caching

    print("All module system examples passed.")


if __name__ == "__main__":
    main()
