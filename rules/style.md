### Key Design Rules

**THESE RULES ARE NON-NEGOTIABLE**

- **No code comments.** Express intent through naming.
- Never write functions that are 1-2 lines **do not write wrapper functions**. A function whose body is a single forwarding call is a wrapper however many callers it has - caller count is a floor, not a warrant, and avoiding duplication is not by itself a reason to extract. If you think a short function is justified because it names a larger process, **ask before writing it**; do not grant yourself that exception.
- A small function is permitted when it **is** the class's core purpose. When the thing a class exists to do is one small operation per kind of thing it handles - a bridge's push functions, one per kind of command - those functions are the class's functionality, not wrappers around it, and dissolving them into their call sites destroys the vocabulary the class exists to provide. The test is whether the function names something the class is *for*: a bridge pushes commands, so its push functions stay however short they are. A function that merely forwards to another class's API is still a wrapper. This exception is **declared, not self-certified** - add the entry to `core_purpose_api` under `[suite]` in the project's `.claude/refactor.toml` so the gate exempts it and the list stays readable as the class's sanctioned API, and **ask before adding one**.
- Never keep a class that is too small to name what it owns. A subclass whose body is a constructor - no overrides, no members of its own - is constructor arguments pretending to be a type; dissolve it into its call site. The same goes for a standalone class holding one function and nothing else. Plain data aggregates and abstract interfaces are not covered by this.
- Never let a virtual be a shell. When a caller reaches a class polymorphically, that virtual is the one function the hierarchy is allowed - the work goes inside each override, not one hop further down.
- Use an enum whenever a property has two or more named states, and whenever two or more terms name the kinds a type comes in. A boolean is for a plain yes/no fact and nothing else - the moment the second state has a name of its own, the states belong in an enum rather than in a bool, an int or a string. Enums describe and label; that is a different job from what a subclass does, which is to modify data, so an enum is never an argument against a subclass family and a type may well want both.
- Never use ternary operators
- Always use {} for blocks
- Always avoid encapsulation on very small segments of code which repeat
- Make sure code fits the class's intended purpose, and generally sticks to a single area of concern
- avoid creating functions with the keyword `inline`
- Avoid using getter and setter functions, prefer public variable access. `private` and `protected` are fine for anything you can guarantee stays inside the class, and choosing them for organisation is legitimate. But the moment a member needs an accessor to be reached, it is not internal: move the member to public scope and delete the accessor.
- Avoid using namespaces
- Never use functions that perform a single operation (single if statement or boolean operation, etc.)
- It is better to declare an unused variable if it still represents some part of the class's immediate functionality
- If you are about to flag a rule deviation in your report, **stop and ask instead**. A disclosed violation is still a violation; reporting it is not permission, and the design-rule hook only machine-checks some of these rules - its silence on the rest is coverage, not a verdict.
