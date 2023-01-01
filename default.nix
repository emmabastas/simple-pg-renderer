{ pkgs ? import <nixpkgs> {} }:

let
  nodeDependencies = (pkgs.callPackage ./npm-deps-nix/default.nix {}).nodeDependencies;

  perl = pkgs.perl.withPackages (p: with p; [
      Mojolicious
      FutureAsyncAwait
      TimeDate
      StringShellQuote
      JSONXS
      CryptJWT
      ProcProcessTable
      DateTime
      DBI
      TieIxHash
      UUIDTiny
      HTMLParser
      GD
      ClassAccessor
      LocaleMaketextLexicon
      CGI
      DataStructureUtil
      MathRandomSecure
      IOSocketSSL
    ]);
in

pkgs.stdenv.mkDerivation {
  name = "webwork-flashcard";

  src = pkgs.fetchFromGitHub {
    owner = "emmabastas";
    repo = "webwork-flashcard";
    rev = "2fe11d7f53a03a7e68b586faa3975942bcb21948";
    sha256 = "sha256-A+9tWopNqtMmAZ9IrzTHRaLftmESSt+6/kootI2WTR8=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  buildInputs = [ perl ];

  postUnpack = ''
    ln -s ${nodeDependencies}/lib/node_modules foo
  '';

  installPhase = ''
    mkdir -p $out
    cp -r bin/ lib/ render_app.conf.dist $out

    wrapProgram $out/bin/webwork-flashcard --prefix PATH : ${pkgs.lib.makeBinPath [ perl ]}
  '';
}
