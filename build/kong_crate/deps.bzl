"""Setup dependencies after repostories are downloaded."""

load("@rules_rust//crate_universe:defs.bzl", "crates_repository")
load("@rules_rust//crate_universe:repositories.bzl", "crate_universe_dependencies")
load("@rules_rust//rust:repositories.bzl", "rules_rust_dependencies", "rust_register_toolchains", "rust_repository_set")

def kong_crate_repositories(cargo_home_isolated = True):
    """
    Setup Kong Crates repostories

    Args:
        cargo_home_isolated (bool): `False` to reuse system CARGO_HOME
        for faster builds. `True` is default and will use isolated
        Cargo home, which takes about 2 minutes to bootstrap.
    """

    rules_rust_dependencies()

    # To get the sha256s, please check out the
    # https://static.rust-lang.org/dist/channel-rust-stable.toml
    rust_register_toolchains(
        edition = "2021",
        extra_target_triples = ["aarch64-unknown-linux-gnu"],
        sha256s = {
            "rustc-1.99.1-x86_64-unknown-linux-gnu.tar.xz": "2ff05ff9c08a90861e7f6e4065b40a8b87463b4576186fd613871c3e37f2091f",
            "clippy-1.99.1-x86_64-unknown-linux-gnu.tar.xz": "458339712a058e52cc4522ff9ef8b59cd1ea1340312216cd94194c464a3f6dc5",
            "cargo-1.99.1-x86_64-unknown-linux-gnu.tar.xz": "53f3521949404d595efb06a55c12c5658d4ed1c75566f33d3d514eaebe70bd8a",
            "llvm-tools-1.99.1-x86_64-unknown-linux-gnu.tar.xz": "8429c5117debfb45c22cf2f97712ef00e0e94976c96cf92f661974a458ca7e84",
            "rust-std-1.99.1-x86_64-unknown-linux-gnu.tar.xz": "109b074225bf5b9ea3820890876bfdf4ed161adbfaf94b2b4b5984c85ee5d958",
            "rustfmt-1.99.1-x86_64-unknown-linux-gnu.tar.xz": "e3b36c4c7ec3486c059d8067ff48787676612007123aad7a4e8ec12c48ee9ba2",
        },
        versions = ["1.99.1"],
    )

    rust_repository_set(
        name = "rust_linux_arm64_linux_tuple",
        edition = "2021",
        exec_triple = "x86_64-unknown-linux-gnu",
        extra_target_triples = ["aarch64-unknown-linux-gnu"],
        sha256s = {
            "rustc-1.99.1-aarch64-unknown-linux-gnu.tar.xz": "acdcdfe09ae1f103aa9a2b7f88903a9588bc2e99288af10e6fbf5514e2e49f25",
            "clippy-1.99.1-aarch64-unknown-linux-gnu.tar.xz": "3bea76c26dcf30c176c0a8a8cc283eb59fabd754e24a68b4ca0701e5f3245f6b",
            "cargo-1.99.1-aarch64-unknown-linux-gnu.tar.xz": "5156832e0c1254e9b49a79edabdc6d4c35f32f8fc1cf3ca700f268ff96087ab0",
            "llvm-tools-1.99.1-aarch64-unknown-linux-gnu.tar.xz": "cd1818058908c1c4e99bd2843fe103df255157454e16186ec9cc3b5b5823b39c",
            "rust-std-1.99.1-aarch64-unknown-linux-gnu.tar.xz": "e25668477083d6a9ddb87b9beb9c00742225f38233ccb4bfba3afa7a07427f52",
            "rustfmt-1.99.1-aarch64-unknown-linux-gnu.tar.xz": "26b3200b1461921415927abf7fe410202a6eda2db3e419abde59e0abfcd93fc2",
        },
        versions = ["1.99.1"],
    )

    crate_universe_dependencies()

    crates_repository(
        name = "atc_router_crate_index",
        cargo_lockfile = "//:crate_locks/atc_router.Cargo.lock",
        # Kong builds Linux/macOS only; retired platform names in older rules_rust
        # cannot be queried by current rustc (for example aarch64-fuchsia).
        supported_platform_triples = [
            "aarch64-unknown-linux-gnu",
            "x86_64-unknown-linux-gnu",
            "aarch64-apple-darwin",
            "x86_64-apple-darwin",
        ],
        isolated = cargo_home_isolated,
        lockfile = "//:crate_locks/atc_router.lock",
        manifests = [
            "@atc_router//:Cargo.toml",
        ],
    )
