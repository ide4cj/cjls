{ lib, stdenv, cangjie, llvmPackages, autoPatchelfHook }:

stdenv.mkDerivation {
  pname = "cjls";
  version = (builtins.fromTOML (builtins.readFile ../modules/cjls/cjpm.toml)).package.version;

  src = ../.;

  nativeBuildInputs = [ cangjie autoPatchelfHook ];
  buildInputs = [ llvmPackages.libcxx stdenv.cc.cc.lib ];

  CANGJIE_HOME = "${cangjie}";

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
    license = with lib.licenses; [ asl20 mit ];
    mainProgram = "cjls";
    platforms = [ "x86_64-linux" ];
  };
}
