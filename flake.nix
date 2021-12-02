{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
      in
      rec {
        packages.ham = pkgs.stdenv.mkDerivation rec {
          src = ./.;
          name = "ham";
          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildPhase = ''
            runHook preInstall
            
            runHook postInstall
          '';
          installPhase = ''
            runHook preInstall
            
            mkdir --parents $out/{bin,opt/${name}}
            cp --recursive Hammer ham $out/opt/${name}
            ln --relative --symbolic $out/opt/${name}/${name} $out/bin

            runHook postInstall
          '';
          postFixup = ''
            wrapProgram $out/opt/${name}/${name} \
              --prefix PERL5LIB : "${with pkgs.perlPackages; makePerlPath [
                BHooksEndOfScope
                GitRepository
                GitVersionCompare
                ModuleImplementation
                ModuleRuntime
                PackageStash
                SubExporterProgressive
                SystemCommand
                TryTiny
                URI
                XMLMini
                namespaceclean
              ]}"
          '';
        };
        defaultPackage = packages.ham;
        apps.ham = flake-utils.lib.mkApp { drv = packages.ham; };
        defaultApp = apps.ham;
      }
    );
}
