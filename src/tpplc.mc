/-
TreePPL Compiler command line
-/

-- (vsenderov, 2923-06-16 I don't remeber what are all the includes for any more;
-- perhaps we should test and see if we need all of them)
include "sys.mc"

include "mexpr/ast.mc"
include "mexpr/ast-builder.mc"
include "mexpr/boot-parser.mc"
include "mexpr/type-check.mc"
include "mexpr/generate-json-serializers.mc"

include "treeppl-to-coreppl/compile.mc"

include "coreppl::dppl-arg.mc" -- inherit cmd-line opts from cppl
include "coreppl::coreppl-to-rootppl/compile.mc"
include "coreppl::build.mc"
include "coreppl::parser.mc"

--lang CorePPLUsage =
--  CPPLBackcompat + LoadRuntime +
--  ImportanceSamplingMethod + BPFMethod + APFMethod +
--  LightweightMCMCMethod  + NaiveMCMCMethod + TraceMCMCMethod +
--	PIMHMethod + ProjMatchPprint
--end

-- (vsenderov, 2023-06-16 The CPPL language as defined in the cppl command line)
lang CPPLLang =
  MExprAst + MExprCompile + TransformDist + MExprEliminateDuplicateCode +
  MExprSubstitute + MExprPPL + GenerateJsonSerializers

  -- Check if a CorePPL program uses infer
  sem hasInfer =
  | expr -> hasInferH false expr
  
  sem hasInferH acc =
  | TmInfer _ -> true
  | expr -> sfold_Expr_Expr hasInferH acc expr

end

lang TreePPLThings = TreePPLAst + TreePPLCompile
  + LowerProjMatch + ProjMatchTypeCheck + ProjMatchPprint
end

-- Command line menu for TreePPL
let tpplMenu = lam. join [
  "Usage: tpplc program.tppl out.mc [<options>]\n\n",
  "Options:\n",
  argHelpOptions config,
  "\n"
] 

mexpr

-- (vsenderov, 2023-06-16 Changed this to CPPLLang as it is in the cppl command line)
-- use CorePPLUsage in
use CPPLLang in

-- Use the arg.mc library to parse arguments
let result = argParse default config in
match result with ParseOK r in
  let options: Options = r.options in
  -- Print menu if not exactly three file arguments
  if neqi (length r.strings) 2 then
    print (tpplMenu ());
    exit 0
  else
    match r.strings with [filename, outName] in
    -- (vsenderov, 2023-06-16) until here the logic follows the cppl command line
    -- The data is an mcore file; that can be parsed with the bootparser
    use BootParser in
    let library = parseMCoreFile {
        defaultBootParserParseMCoreFileArg with eliminateDeadCode = false, allowFree = true
      } "src/lib/standard.mc" in
    let internals = parseMCorePPLFileLib options.test "src/lib/internals.mc" in

    -- However, now filename is a tppl program so it has to be parsed with TreePPLThings
    let content = readFile filename in
    use TreePPLThings in
    match parseTreePPLExn filename content with  file in
    let corePplAst: Expr = compile library internals file in
    -- TODO(vsenderov, 2023-08-08) serialization/ deserialization
    -- match compile input file with (corePplAst, modelTypes) in
    let modelTypes = [ tyseq_ tybool_, tyfloat_ ] in 
    -- However for user defined types, due to symbolize, we cannot show a hardcoded example here
    -- now we can run addJsonSerializers which returns three things:
    -- result, which is a Map from the Type to the Serializer/Deserializer thing
    -- the AST
    -- an environment, which contains the handles to the serializers and deserializers
    --match addJsonSerializers modelTypes corePplAst with (result, corePplAst, envir) in
    -- print (mexprPPLToString corePplAst);
    --match mapLookup (tyseq_ tybool_) result with Some s in
    --match mapLookup (tyfloat_) result with Some r in
    -- print (mexprPPLToString s.serializer);
    

-- Replace the placeholder with the actual serializer
---let modifiedAst = replaceSerializerPlaceholder r.serializer corePplAst in

-- Continue with further processing using modifiedAst

    
    let prog: Expr = typeCheck corePplAst in
    let prog: Expr = lowerProj prog in
    -- Now we have the coreppl AST. Can we follow the cppl logic again?
    let ast = prog in
    let noInfer = not (hasInfer ast) in
    if eqString options.target "rootppl" then
      if noInfer then
        let ast =
          if options.transform then transform ast
          else ast
        in
        let ast = rootPPLCompile options ast in
        buildRootPPL options ast
      else error "Use of infer is not supported by RootPPL backend"

    else
      let ast = mexprCpplCompile options noInfer ast in
    --dprint corePplAst;
    --printLn (mexprPPLToString corePplAst);

    --(vsenderov, 2023-06-16 We use our own output for now for now)
      writeFile outName (use MExpr in concat "mexpr\n" (mexprToString ast));
      

      -- Output the compiled OCaml code (unless --skip-final is specified)
      -- let xx = if options.skipFinal then
      --   -- print (join ["Miking output written.\n", "To get an executable, compile with \n\n  mi compile ",outName, "\n\n"]);
      --   ()
      -- else sysRunCommand ["mi", "compile", outName] "" ".";
      --   -- print (join ["Executable compiled.\n", "To run \n\n  ./out \n\n"]);
      --   ()
      -- in
      -- print (concat (mexprPPLToString corePplAst) "\n\n");
      ()
