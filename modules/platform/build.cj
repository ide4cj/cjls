// cjpm runs this around every build and test of `platform`, from its directory. A multiplatform
// module's library and `.cjo` are in `<target>/<profile>/platform/src/<set>/product/`, where
// `cjpm build` looks for them and `cjpm test` does not: it neither imports nor links a dependency
// from there (cangjie_tools 3009d063, `test.cj:579`, `:681`), and a test of a module using
// `platform` fails. After each build both are copied up to `<target>/<profile>/platform/`, where
// it does (D99). cjpm tells a script no target directory: every one under `target` is seen to.
import std.env.*
import std.fs.*

const TARGET = "../../target"
const NAME = "platform"

main(): Int64 {
    if (getCommandLine().get(1) == "post-build") {
        liftProducts(Path(TARGET))
    }
    0
}

func liftProducts(dir: Path): Unit {
    if (!exists(dir)) {
        return
    }
    for (entry in Directory.readFrom(dir) where entry.isDirectory()) {
        if (entry.name == NAME && exists(entry.path.join("src"))) {
            liftProduct(entry.path)
        } else {
            liftProducts(entry.path)
        }
    }
}

// the one product set a build compiled, its files beside `src`
func liftProduct(module: Path): Unit {
    for (set in Directory.readFrom(module.join("src")) where set.isDirectory()) {
        let product = set.path.join("product")
        for (file in ["lib${NAME}.a", "${NAME}.cjo"] where exists(product.join(file))) {
            copy(product.join(file), to: module.join(file), overwrite: true)
        }
    }
}
