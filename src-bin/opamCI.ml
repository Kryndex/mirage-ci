(*---------------------------------------------------------------------------
   Copyright (c) 2016 Anil Madhavapeddy. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

open !Astring

open DataKitCI

let logs = Main.logs

module Builder = struct

  open Term.Infix

  let one_hour = 60. *. 60.
  let three_hours = one_hour *. 3.
  let opam_repo = ProjectID.v ~user:"ocaml" ~project:"opam-repository"
  let primary_ocaml_version = "4.04.0"
  let compiler_variants = ["4.01.0";"4.02.3";"4.03.0";"4.04.0_flambda"]

  let pool = Monitored_pool.create "docker" 24

  let label = "ocaml" 
  let docker_t = Docker_build.config ~logs ~label ~pool ~timeout:one_hour
  let docker_run_t = Docker_run.config ~logs ~label ~pool ~timeout:one_hour
  let opam_t = Opam_build.config ~logs ~label

  let build_opam_pkg image pkg =
    let open !Dockerfile in
    let dfile =
      from image.Docker_build.sha256 @@
      run "opam depext -iyv -j 2 %s" pkg in
    let hum = Fmt.strf "opam install %s" pkg in
    Docker_build.run docker_t ~hum dfile

  let ignore_failure ~on_fail t =
   Term.state t >>= function
   | Error (`Pending m) -> Term.pending "%s" m
   | Error (`Failure m) -> Term.return (on_fail m)
   | Ok m -> Term.return m

  let build_all_pkgs image pkgs =
    String.cuts ~empty:false ~sep:"\n" pkgs |>
    List.map (fun pkg ->
      let t = build_opam_pkg image pkg in
      pkg, t
    ) |>
    Term.wait_for_all |>
    ignore_failure ~on_fail:(fun _ -> ())

  let list_all_pkgs image =
    let cmd = ["opam";"list";"-a";"-s"] in
    Docker_run.run ~tag:image.Docker_build.sha256 ~cmd docker_run_t

  let report ~order ~label t =
    let l = Fmt.strf "%d %s" order label in
    let t = t >>= fun _ -> Term.return label in
    l, t

  let opam_build_all target =
    let distro = "ubuntu-16.04" in
    let base_dfile ~ocaml_version = 
      let open Dockerfile in
      from ~tag:(distro^"_ocaml-"^ocaml_version) "ocaml/opam" @@
      workdir "/home/opam/opam-repository" @@
      run "git pull origin master" @@
      run "opam update" @@
      run "opam admin make" @@
      run "opam depext -uivy ocamlfind"
    in
    let bulk_build ~ocaml_version =
      Docker_build.run docker_t ~hum:(Fmt.strf "Base for %s" ocaml_version) (base_dfile ~ocaml_version)
      >>= fun img ->
      list_all_pkgs img
      >>= fun pkgs ->
      build_all_pkgs img pkgs
    in
    let all_tests = [
      report ~order:1 ~label:"4.03.0" (bulk_build ~ocaml_version:"4.03.0");
      report ~order:2 ~label:"4.04.0" (bulk_build ~ocaml_version:"4.04.0");
      report ~order:3 ~label:"4.02.3" (bulk_build ~ocaml_version:"4.02.3");
    ] in
    match DataKitCI.Target.Full.id target with
    |`Ref r when Datakit_path.to_hum r = "tags/bulk" -> all_tests
    | _ -> []

  let tests = [
    Config.project ~id:"mirage/opam-repository" opam_build_all;
  ]
end

(* Command-line parsing *)

let web_config =
  Web.config
    ~name:"opam-ci"
    ~can_read:ACL.(everyone)
    ~can_build:ACL.(username "admin")
    ~state_repo:(Uri.of_string "https://github.com/mirage/opam-ci.logs")
    ()

let () =
  Main.run (Cmdliner.Term.pure (Config.ci ~web_config ~projects:Builder.tests))

(*---------------------------------------------------------------------------
   Copyright (c) 2016 Anil Madhavapeddy
   Copyright (c) 2016 Thomas Leonard

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
