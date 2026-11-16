{
  lib,
  stdenv,
  cangjie,
  stdx,
  llvmPackages,
  autoPatchelfHook,
  makeWrapper,
  git,
  fetchgit,
  which,
}:
let
  lock = builtins.fromTOML (builtins.readFile ../cjpm.lock);
  # FIXME(https://github.com/ide4cj/cangjie-nix/issues/46): Move lock file parsing and cache generation to cangjie-nix.
  # cjpm.lock has no Nix content hashes; decide how to supply them there.
  gitHashes = {
    jian = "sha256-I30UBYP3/yAlO9DmeBPcF/N1Y9ppu6klSqJR4TjOZiU=";
  };
  gitDependencies = lib.mapAttrsToList (
    name: dependency:
    let
      source = builtins.match "git\\+(.+)#([0-9a-f]{40})" dependency.source;
    in
    if source == null then
      throw "Unsupported cjpm.lock source for ${name}: ${dependency.source}"
    else
      let
        rev = builtins.elemAt source 1;
      in
      {
        inherit name rev;
        checkout = fetchgit {
          url = builtins.elemAt source 0;
          inherit rev;
          hash = gitHashes.${name};
          leaveDotGit = true;
          fetchSubmodules = false;
        };
      }
  ) (lock.requires or { });
in

stdenv.mkDerivation {
  pname = "cjls";
  version = (builtins.fromTOML (builtins.readFile ../modules/cjls/cjpm.toml)).package.version;

  src = ../.;

  nativeBuildInputs = [
    cangjie
    autoPatchelfHook
    makeWrapper

    git
    which
  ];
  buildInputs = [
    llvmPackages.libcxx
    stdenv.cc.cc.lib
  ];

  CANGJIE_HOME = "${cangjie}";
  CANGJIE_STDX_PATH = "${stdx}/stdx";

  preBuild = ''
    cacheDir="$TMPDIR/cjpm-cache"
    mkdir -p "$cacheDir/git"
    ${lib.concatMapStringsSep "\n" (dependency: ''
      mkdir -p "$cacheDir/git"/${lib.escapeShellArg dependency.name}
      cp -R ${dependency.checkout} "$cacheDir/git"/${lib.escapeShellArg "${dependency.name}/${dependency.rev}"}
    '') gitDependencies}
    chmod -R u+w "$cacheDir"
    cat > cangjie-repo.toml <<EOF
    [repository.cache]
    path = "$cacheDir"
    EOF
  '';

  buildPhase = ''
    runHook preBuild
    cjpm build -j "$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 target/release/bin/cjls "$out/bin/cjls"
    runHook postInstall
  '';

  meta = {
    description = "Language server for Cangjie";
    homepage = "https://github.com/ide4cj/cjls";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "cjls";
  };
}
