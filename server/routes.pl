:- module(routes,[]).

/** <module> HTTP API
 *
 * The Terminus DB API interface.
 *
 * A RESTful endpoint inventory for weilding the full capabilities of the
 * terminusDB.
 *
 * * * * * * * * * * * * * COPYRIGHT NOTICE  * * * * * * * * * * * * * * *
 *                                                                       *
 *  This file is part of TerminusDB.                                     *
 *                                                                       *
 *  TerminusDB is free software: you can redistribute it and/or modify   *
 *  it under the terms of the GNU General Public License as published by *
 *  the Free Software Foundation, under version 3 of the License.        *
 *                                                                       *
 *                                                                       *
 *  TerminusDB is distributed in the hope that it will be useful,        *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of       *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        *
 *  GNU General Public License for more details.                         *
 *                                                                       *
 *  You should have received a copy of the GNU General Public License    *
 *  along with TerminusDB.  If not, see <https://www.gnu.org/licenses/>. *
 *                                                                       *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

%% TODO: this module should really only need things from core/api and maybe core/account.

% Default utils
:- use_module(core(util/utils)).
% File processing
:- use_module(core(util/file_utils), [terminus_path/1]).
:- reexport(core(util/syntax)).

% Database utils
:- use_module(core(triple/database_utils)).
% Dumping turtle
:- use_module(core(triple/turtle_utils)).

% woql libraries
:- use_module(core(query/woql_compile)).
% Frame and document processing
:- use_module(core(query/frame)).
:- use_module(core(query/ask)).
% JSON manipulation
:- use_module(core(query/jsonld)).
% JSON Queries
:- use_module(core(query/json_woql)).

:- use_module(core(transaction/descriptor)).
% Database construction utils
:- use_module(core(transaction/database)).
% Validation
:- use_module(core(transaction/validate)).

:- use_module(core(api/db_init)).
:- use_module(core(api/db_delete)).

% Load capabilities library
:- use_module(core(account/capabilities)).

:- use_module(library(jwt/jwt_dec)).

% http libraries
:- use_module(library(http/http_log)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_server_files)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_path)).
:- use_module(library(http/html_head)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_header)).
:- use_module(library(http/http_cors)).
:- use_module(library(http/json)).
:- use_module(library(http/json_convert)).

% multipart
:- use_module(library(http/http_multipart_plugin)).

% Authentication library is only half used.
% and Auth is custom, not actually "Basic"
% Results should be cached!
:- use_module(library(http/http_authenticate)).


%%%%%%%%%%%%% API Paths %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Set base location
% We may want to allow this as a setting...
:- multifile http:location/3.
:- dynamic http:location/3.
http:location(root, '/', []).

%%%%%%%%%%%%%%%%%%%% Connection Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(.), cors_catch(connect_handler(Method)),
                [method(Method),
                 methods([options,get])]).

/**
 * connect_handler(+Method,+Request:http_request) is det.
 */
connect_handler(options,_Request) :-
    % TODO: What should this be?
    % Do a search for each config:public_server_url
    % once you know.
    config:public_server_url(SURI),
    open_descriptor(terminus_descriptor{}, DB),
    write_cors_headers(SURI, DB),
    format('~n').
connect_handler(get,Request) :-
    config:public_server_url(SURI),
    connection_authorised_user(Request,User,SURI),
    open_descriptor(terminus_descriptor{}, DB),
    write_cors_headers(SURI, DB),
    reply_json(User).


%%%%%%%%%%%%%%%%%%%% Console Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(console), cors_catch(console_handler(Method)),
                [method(Method),
                 methods([options,get])]).

/*
 * console_handler(+Method,+Request) is det.
 */
console_handler(options,_Request) :-
    config:public_server_url(SURI),
    open_descriptor(terminus_descriptor{}, DB),
    write_cors_headers(SURI, DB),
    format('~n').
console_handler(get,_Request) :-
    terminus_path(Path),
    interpolate([Path,'/config/index.html'], Index_Path),
    read_file_to_string(Index_Path, String, []),
    config:public_server_url(SURI),
    open_descriptor(terminus_descriptor{}, DB),
    write_cors_headers(SURI, DB),
    format('~n'),
    write(String).

%%%%%%%%%%%%%%%%%%%% Message Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(message), cors_catch(message_handler(Method)),
                [method(Method),
                 methods([options,get,post])]).


/*
 * message_handler(+Method,+Request) is det.
 */
message_handler(options,_Request) :-
    config:public_server_url(SURI),
    open_descriptor(terminus_descriptor{}, DB),
    write_cors_headers(SURI, DB),
    format('~n').
message_handler(get,Request) :-
    try_get_param('terminus:message',Request,Message),

    with_output_to(
        string(Payload),
        json_write(current_output, Message, [])
    ),

    http_log('~N[Message] ~s~n',[Payload]),

    config:public_server_url(SURI),
    open_descriptor(terminus_descriptor{}, DB),
    write_cors_headers(SURI, DB),

    reply_json(_{'terminus:status' : 'terminus:success'}).
message_handler(post,R) :-
    add_payload_to_request(R,Request), % this should be automatic.
    try_get_param('terminus:message',Request,Message),

    with_output_to(
        string(Payload),
        json_write(current_output, Message, [])
    ),

    http_log('~N[Message] ~s~n',[Payload]),

    config:public_server_url(SURI),
    open_descriptor(terminus_descriptor{}, DB),
    write_cors_headers(SURI, DB),

    reply_json(_{'terminus:status' : 'terminus:success'}).

%%%%%%%%%%%%%%%%%%%% Database Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(db/DB_Name), cors_catch(db_handler(Method, DB_Name)),
                [method(Method),
                 methods([options,post,delete])]).


/**
 * db_handler(Method:atom,DB:atom,Request:http_request) is det.
 */
db_handler(options,_DB,_Request) :-
    % database may not exist - use server for CORS
    config:public_server_url(SURI),
    open_descriptor(terminus_descriptor{}, DB),
    write_cors_headers(SURI,DB),
    format('~n').
db_handler(post,DB,R) :-
    add_payload_to_request(R,Request), % this should be automatic.
    open_descriptor(terminus_descriptor{}, Terminus_DB),
    /* POST: Create database */
    authenticate(Terminus_DB, Request, Auth),
    config:public_server_url(Server),
    verify_access(Terminus_DB, Auth, terminus:create_database,Server),
    try_get_param('terminus:base_uri',Request,Base_URI),
    try_create_db(DB,Base_URI),
    write_cors_headers(Server, Terminus_DB),
    reply_json(_{'terminus:status' : 'terminus:success'}).
db_handler(delete,DB,Request) :-
    /* DELETE: Delete database */
    open_descriptor(terminus_descriptor{}, Terminus_DB),
    authenticate(Terminus_DB, Request, Auth),

    config:public_server_url(Server),

    verify_access(Terminus_DB, Auth, terminus:delete_database,Server),

    try_delete_db(DB),

    write_cors_headers(Server, Terminus_DB),

    reply_json(_{'terminus:status' : 'terminus:success'}).

%%%%%%%%%%%%%%%%%%%% Schema Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(schema/DB), cors_catch(schema_handler(Method,DB)),
                [method(Method),
                 time_limit(infinite),
                 methods([options,get,post])]).
:- http_handler(root(schema/DB/Branch), cors_catch(schema_handler(Method,DB,Branch)),
                [method(Method),
                 time_limit(infinite),
                 methods([options,get,post])]).
:- http_handler(root(schema/DB/Branch/Graph), cors_catch(schema_handler(Method,DB,Branch,Graph)),
                [method(Method),
                 time_limit(infinite),
                 methods([options,get,post])]).

/*
 * schema_handler(Mode,DB,Request) is det.
 *
 * Get or update a schema.
 */
schema_handler(options,DB,_Request) :-
    open_descriptor(terminus_descriptor{}, Terminus),
    try_db_uri(DB,DB_URI),
    write_cors_headers(DB_URI, Terminus),
    format('~n'). % send headers
schema_handler(get,DB,Request) :-
    open_descriptor(terminus_descriptor{}, Terminus),
    /* Read Document */
    authenticate(Terminus,Request,Auth),

    % We should make it so we can pun documents and IDs

    try_db_uri(DB,DB_URI),

    % check access rights
    verify_access(Terminus,Auth,terminus:get_schema,DB_URI),

    % Let's do a default schema if we can't find one.
    catch(
        try_get_param('terminus:schema',Request,Name),
        _,
        interpolate([DB_URI,'/schema'],Name)
    ),

    try_dump_schema(DB_URI, Terminus, Name, Request).
schema_handler(post,DB,R) :- % should this be put?
    add_payload_to_request(R,Request), % this should be automatic.
    open_descriptor(terminus_descriptor{}, Terminus),
    /* Read Document */
    authenticate(Terminus,Request,Auth),

    % We should make it so we can pun documents and IDs
    try_db_uri(DB,DB_URI),

    % check access rights
    verify_access(Terminus,Auth,terminus:update_schema,DB_URI),

    try_get_param('terminus:schema',Request,Name),
    try_get_param('terminus:turtle',Request,TTL),

    try_update_schema(DB_URI,Name,TTL,Witnesses),

    reply_with_witnesses(DB_URI,Terminus,Witnesses).

/*
 * schema_handler(Mode,DB,Branch,Request) is det.
 *
 * Get or update a schema.
 */
schema_handler(_Method,_DB,_Branch,_Request) :-
    throw(error('Unimplemented')).

/*
 * schema_handler(Mode,DB,Branch,Graph,Request) is det.
 *
 * Get or update a schema.
 */
schema_handler(_Method,_DB,_Branch,_Graph,_Request) :-
    throw(error('Unimplemented')).

%%%%%%%%%%%%%%%%%%%% Frame Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(frame/DB), cors_catch(frame_handler(Method,DB)),
                [method(Method),
                 methods([options,get])]).
:- http_handler(root(frame/DB/Branch), cors_catch(frame_handler(Method,DB,Branch)),
                [method(Method),
                 methods([options,get])]).

/**
 * frame_handler(+Mode, +DB, +Class_ID, +Request:http_request) is det.
 *
 * Establishes frame responses
 */
frame_handler(options,DB,_Request) :-
    open_descriptor(terminus_descriptor{}, Terminus),
    try_db_uri(DB,DB_URI),
    write_cors_headers(DB_URI, Terminus),
    format('~n'). % send headers
frame_handler(get, DB, Request) :-
    open_descriptor(terminus_descriptor{}, Terminus),
    /* Read Document */
    authenticate(Terminus, Request, Auth),

    % We should make it so we can pun documents and IDs

    try_db_uri(DB,DB_URI),

    % check access rights
    verify_access(Terminus,Auth,terminus:class_frame,DB_URI),

    try_db_graph(DB_URI,Database),

    try_get_param('terminus:class',Request,Class_URI),

    try_class_frame(Class_URI,Database,Frame),

    config:public_server_url(SURI),
    write_cors_headers(SURI, Terminus),
    reply_json(Frame).

frame_handler(_Method,_DB,_Branch,_Request) :-
    throw(error('Unimplemented')).


%%%%%%%%%%%%%%%%%%%% Document Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(document/DB_ID), cors_catch(document_handler(Method,DB_ID)),
                [method(Method),
                 methods([options,post,get,delete])]).
:- http_handler(root(document/DB_ID/Branch_ID), cors_catch(document_handler(Method,DB_ID,Branch_ID)),
                [method(Method),
                 methods([options,post,get,delete])]).
:- http_handler(root(document/DB_ID/Branch_ID/Doc_Or_Graph_ID), cors_catch(create_document_handler(Method,DB_ID,Branch_ID,Doc_Or_Graph_ID)),
                [method(Method),
                 methods([options,post,get,delete])]).

/**
 * document_handler(+Mode, +DB, +Doc_ID, +Request:http_request) is det.
 *
 */
document_handler(options,DB,_Doc_ID,_Request) :-
    open_descriptor(terminus_descriptor{}, Terminus),
    try_db_uri(DB,DB_URI),
    write_cors_headers(DB_URI, Terminus),
    format('~n').
document_handler(get, DB, Doc_ID, Request) :-
    open_descriptor(terminus_descriptor{}, Terminus),
    /* Read Document */
    authenticate(Terminus, Request, Auth),

    % We should make it so we can pun documents and IDs

    try_db_uri(DB,DB_URI),

    % check access rights
    verify_access(Terminus,Auth,terminus:get_document,DB_URI),

    try_db_graph(DB_URI,Database),

    try_doc_uri(DB_URI,Doc_ID,Doc_URI),

    % This feels a bit ugly... but perhaps not
    (   get_param('terminus:encoding',Request,'terminus:frame')
    ->  try_get_filled_frame(Doc_URI,Database,JSON),
        %http_log('Writing Frame JSON-LD:', []),
        %json_write_dict(Log,JSON),
        true
    ;   try_get_document(Doc_URI,Database,JSON)
    ),
    write_cors_headers(DB_URI, Terminus),
    reply_json_dict(JSON).
document_handler(post, DB, Doc_ID, R) :-
    add_payload_to_request(R,Request),

    open_descriptor(terminus_descriptor{}, Terminus),
    /* Update Document */
    authenticate(Terminus, Request, Auth),

    try_db_uri(DB,DB_URI),

    % check access rights
    verify_access(Terminus,Auth,terminus:create_document,DB_URI),

    try_db_graph(DB_URI, Database),

    try_get_param('terminus:document',Request,Doc),

    % very hacky!
    interpolate(['doc:',Doc_ID],Doc_URI),

    try_update_document(Terminus, Doc_URI,Doc,Database,Witnesses),

    reply_with_witnesses(DB_URI,Terminus,Witnesses).
document_handler(delete, DB, Doc_ID, Request) :-
    open_descriptor(terminus_descriptor{}, Terminus),
    /* Delete Document */
    authenticate(Terminus, Request, Auth),
    % We should make it so we can pun documents and IDs

    try_db_uri(DB,DB_URI),

    % check access rights
    verify_access(Terminus,Auth,terminus:delete_document,DB_URI),

    try_db_graph(DB_URI,Database),

    % very hacky!
    interpolate(['doc:',Doc_ID],Doc_URI),

    try_delete_document(Doc_URI,Database,Witnesses),

    reply_with_witnesses(DB_URI,Terminus,Witnesses).


document_handler(_Method,_DB,_Branch,_Request) :-
    throw(error('Not implemented')).

document_handler(_Method,_DB,_Branch,_Doc_or_Graph,_Request) :-
    throw(error('Not implemented')).



%%%%%%%%%%%%%%%%%%%% WOQL Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(woql/Account_ID/DB_ID), cors_catch(woql_handler(Method,Account_ID,DB_ID)),
                [method(Method),
                 time_limit(infinite),
                 methods([options,post])]).
:- http_handler(root(woql/Account_ID/DB_ID/Ref_ID), cors_catch(woql_handler(Method,Account_ID,DB_ID,Ref_ID)),
                [method(Method),
                 time_limit(infinite),
                 methods([options,post])]).

/**
 * woql_handler(+Method:atom, +Account_ID:user, +DB:database, +Request:http_request) is det.
 */
woql_handler(options,_Account_ID,_DB,_Request) :-
    config:public_server_url(SURI),
    open_descriptor(terminus_descriptor{}, Terminus),
    write_cors_headers(SURI, Terminus),
    format('~n').
woql_handler(post,_Account_ID,DB,R) :-
    add_payload_to_request(R,Request),

    open_descriptor(terminus_descriptor{}, Terminus_Transaction_Object),

    authenticate(Terminus_Transaction_Object, Request, Auth),

    try_db_uri(DB,DB_URI),

    % redundant?
    verify_access(Terminus_Transaction_Object, Auth, terminus:woql_select, DB_URI),

    try_get_param('terminus:query',Request,Atom_Query),
    http_log('~N[Query] ~s~n',[Atom_Query]),

    atom_json_dict(Atom_Query, Query, []),

    jsonld_to_ast_and_context(Query, AST, Ctx),

    active_graphs(AST, Active),

    % TODO: check_capabilities/2 doesn't exist but it should
    check_capabilities(Terminus_Transaction_Object, Active),

    collect_posted_files(Request,Files),
    New_Ctx = Ctx.put(files,Files),

    (   run_query(Query,New_Ctx,JSON)
    ->  true
    ;   JSON = _{bindings : []}),

    config:public_server_url(SURI),
    write_cors_headers(SURI, Terminus_Transaction_Object),
    reply_json_dict(JSON).


woql_handler(_Method,_DB,_Ref,_Request) :-
    throw(error('Not implemented')).

%%%%%%%%%%%%%%%%%%%% Clone Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(clone), cors_catch(clone_handler(Method)),
                [method(Method),
                 time_limit(infinite),
                 methods([options,get])]).
:- http_handler(root(clone/New_DB_ID), cors_catch(clone_handler(Method,New_DB_ID)),
                [method(Method),
                 time_limit(infinite),
                 methods([options,get])]).

clone_handler(_Method,_Request) :-
    throw(error('Not implemented')).

clone_handler(_Method,_DB_ID,_Request) :-
    throw(error('Not implemented')).

%%%%%%%%%%%%%%%%%%%% Fetch Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(fetch/DB_ID/Repo_ID), cors_catch(fetch_handler(Method,DB_ID,Repo_ID)),
                [method(Method),
                 methods([options,post])]).

fetch_handler(_Method,_DB_ID,_Repo,_Request) :-
    throw(error('Not implemented')).


%%%%%%%%%%%%%%%%%%%% Rebase Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(rebase/DB_ID/Branch_ID), cors_catch(rebase_handler(Method,DB_ID,Branch_ID)),
                [method(Method),
                 methods([options,post])]).
:- http_handler(root(rebase/DB_ID/Branch_ID/Remote_ID), cors_catch(rebase_handler(Method,DB_ID,Branch_ID,Remote_ID)),
                [method(Method),
                 methods([options,post])]).

rebase_handler(_Method,_DB_ID,_Request) :-
    throw(error('Not implemented')).

rebase_handler(_Method,_DB_ID,_Repo,_Request) :-
    throw(error('Not implemented')).

%%%%%%%%%%%%%%%%%%%% Push Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(push/DB_ID/Branch_ID), cors_catch(push_handler(Method,DB_ID,Branch_ID)),
                [method(Method),
                 methods([options,post])]).
:- http_handler(root(push/DB_ID/Branch_ID/Remote_ID), cors_catch(push_handler(Method,DB_ID,Branch_ID,Remote_ID)),
                [method(Method),
                 methods([options,post])]).

push_handler(_Method,_DB_ID,_Branch_ID,_Request) :-
    throw(error('Not implemented')).

push_handler(_Method,_DB_ID,_Branch_ID,_Remote_ID,_Request) :-
    throw(error('Not implemented')).


%%%%%%%%%%%%%%%%%%%% Branch Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(branch/DB_ID/New_Branch_ID), cors_catch(branch_handler(Method,DB_ID,New_Branch_ID)),
                [method(Method),
                 methods([options,post])]).

branch_handler(_Method,_DB_ID,_New_Branch_ID,_Request) :-
    throw(error('Not implemented')).

%%%%%%%%%%%%%%%%%%%% Create/Delete Graph Handlers %%%%%%%%%%%%%%%%%%%%%%%%%
:- http_handler(root(branch/DB_ID/Branch_ID/Graph_Type/Graph_ID), cors_catch(graph_handler(Method,DB_ID,Branch_ID,Graph_Type,Graph_ID)),
                [method(Method),
                 methods([options,post,delete])]).

graph_handler(_Method,_DB_ID,_Branch_ID,_Graph_Type,_Graph_ID,_Request) :-
    throw(error('Not implemented')).


%%%%%%%%%%%%%%%%%%%% JSON Reply Hackery %%%%%%%%%%%%%%%%%%%%%%

% We want to use cors whenever we're throwing an error.
:- set_setting(http:cors, [*]).

% Evil mechanism for catching, putting CORS headers and re-throwing.
:- meta_predicate cors_catch(1,?).
cors_catch(Goal,Request) :-
    catch(call(Goal, Request),
          E,
          (   cors_enable,
              http_log('~N[Error] ~q~n',[E]),
              customise_error(E)
          )
         ),
    !.
cors_catch(_,_Request) :-
    % Probably should extract the path from Request
    reply_json(_{'terminus:status' : 'terminus:failure',
                 'terminus:message' : _{'@type' : 'xsd:string',
                                        '@value' : 'Resource not found'}},
               [status(400)]).

customise_error(syntax_error(M)) :-
    format(atom(OM), '~q', [M]),
    reply_json(_{'terminus:status' : 'terminus:failure',
                 'terminus:witnesses' : [_{'@type' : 'vio:ViolationWithDatatypeObject',
                                           'vio:literal' : OM}]},
               [status(400)]).
customise_error(error(syntax_error(M),_)) :-
    format(atom(OM), '~q', [M]),
    reply_json(_{'terminus:status' : 'terminus:failure',
                 'terminus:witnesses' : [_{'@type' : 'vio:ViolationWithDatatypeObject',
                                           'vio:literal' : OM}]},
               [status(400)]).
customise_error(error(syntax_error(M))) :-
    format(atom(OM), '~q', [M]),
    reply_json(_{'terminus:status' : 'terminus:failure',
                 'terminus:witnesses' : [_{'@type' : 'vio:ViolationWithDatatypeObject',
                                           'vio:literal' : OM}]},
               [status(400)]).
customise_error(error(type_error(T,O),C)) :-
    format(atom(M),'Type error for ~q which should be ~q with context ~q', [O,T,C]),
    format(atom(OA), '~q', [O]),
    format(atom(TA), '~q', [T]),
    reply_json(_{'terminus:status' : 'terminus:failure',
                 'terminus:witnesses' : [_{'@type' : 'vio:ViolationWithDatatypeObject',
                                           'vio:message' : M,
                                           'vio:type' : TA,
                                           'vio:literal' : OA}]},
               [status(400)]).
customise_error(graph_sync_error(JSON)) :-
    reply_json(JSON,[status(500)]).
%customise_error((method_not_allowed(
customise_error(http_reply(method_not_allowed(JSON))) :-
    reply_json(JSON,[status(405)]).
customise_error(http_reply(not_found(JSON))) :-
    reply_json(JSON,[status(404)]).
customise_error(http_reply(authorize(JSON))) :-
    reply_json(JSON,[status(401)]).
customise_error(http_reply(not_acceptable(JSON))) :-
    reply_json(JSON,[status(406)]).
customise_error(time_limit_exceeded) :-
    reply_json(_{'terminus:status' : 'teriminus:error',
                 'terminus:message' : 'Connection timed out'
               },
               [status(408)]).
customise_error(error(E)) :-
    format(atom(EM),'Error: ~q', [E]),
    reply_json(_{'terminus:status' : 'terminus:failure',
                 'terminus:message' : EM},
               [status(500)]).
customise_error(error(E, CTX)) :-
    format(atom(EM),'Error: ~q in CTX ~q', [E, CTX]),
    reply_json(_{'terminus:status' : 'terminus:failure',
                 'terminus:message' : EM},
               [status(500)]).
customise_error(E) :-
    throw(E).

%%%%%%%%%%%%%%%%%%%% Access Rights %%%%%%%%%%%%%%%%%%%%%%%%%

/*
 *  fetch_authorization_data(+Request, -KS) is semi-determinate.
 *
 *  Fetches the HTTP Basic Authorization data
 */
fetch_authorization_data(Request, Username, KS) :-
    memberchk(authorization(Text), Request),
    http_authorization_data(Text, basic(Username, Key)),
    coerce_literal_string(Key, KS).

/*
 *  fetch_jwt_data(+Request, -Username) is semi-determinate.
 *
 *  Fetches the HTTP JWT data
 */
fetch_jwt_data(Request, Username) :-
    memberchk(authorization(Text), Request),
    pattern_string_split(" ", Text, ["Bearer", Token]),
    getenv("TERMINUS_JWT_SECRET", JWT_Secret),
    jwt_dec(Token, json{k: JWT_Secret, kty: "oct"}, Payload),
    Username = Payload.get('username').



/*
 * authenticate(+Database, +Request, -Auth_Obj) is det.
 *
 * This should either bind the Auth_Obj or throw an http_status_reply/4 message.
 */
authenticate(DB, Request, Auth) :-
    fetch_authorization_data(Request, Username, KS),
    (   user_key_auth(DB, Username, KS, Auth)
    ->  true
    ;   throw(http_reply(authorize(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : 'Not a valid key'})))).
authenticate(DB, Request, Auth) :-
    % Try JWT if no http keys
    fetch_jwt_data(Request, Username),
    !,
    (   username_auth(DB, Username, Auth)
    ->  true
    ;   throw(http_reply(authorize(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : 'Not a valid key'})))).
authenticate(_, _, _) :-
    throw(http_reply(method_not_allowed(_{'terminus:status' : 'terminus:failure',
                                          'terminus:message' : "No authentication supplied",
                                          'terminus:object' : 'authenticate'}))).


verify_access(DB, Auth, Action, Scope) :-
    (   auth_action_scope(DB, Auth, Action, Scope)
    ->  true
    ;   format(atom(M),'Call was: ~q', [verify_access(Auth, Action, Scope)]),
        throw(http_reply(method_not_allowed(_{'terminus:status' : 'terminus:failure',
                                              'terminus:message' : M,
                                              'terminus:object' : 'verify_access'})))).

connection_authorised_user(Request, Username, SURI) :-
    open_descriptor(terminus_descriptor{}, DB),
    fetch_authorization_data(Request, Username, KS),
    (   user_key_user_id(DB, Username, KS, User_ID)
    ->  (   authenticate(DB, Request, Auth),
            verify_access(Auth,DB,terminus:get_document,SURI)
        ->  true
        ;   throw(http_reply(method_not_allowed(_{'terminus:status' : 'terminus:failure',
                                                  'terminus:message' : 'Bad user object',
                                                  'terminus:object' : User_ID}))))
    ;   throw(http_reply(authorize(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : 'Not a valid key',
                                     'terminus:object' : KS})))).

%%%%%%%%%%%%%%%%%%%% Response Predicates %%%%%%%%%%%%%%%%%%%%%%%%%

/*
 * reply_with_witnesses(+Resource_URI,+Witnesses) is det.
 *
 */
reply_with_witnesses(Resource_URI, DB, Witnesses) :-
    write_cors_headers(Resource_URI, DB),

    (   Witnesses = []
    ->  reply_json(_{'terminus:status' : 'terminus:success'})
    ;   reply_json(_{'terminus:status' : 'terminus:failure',
                     'terminus:witnesses' : Witnesses},
                   [status(406)])
    ).


/********************************************************
 * Determinising predicates used in handlers            *
 *                                                      *
 * It's not fun to fail, so don't!                      *
 ********************************************************/


/*
 * try_get_document(ID, Database, Object) is det.
 *
 * Actually has determinism: det + error
 *
 * Gets document (JSON-LD) associated with ID
 */
try_get_document(ID,Database,Object) :-
    (   document_jsonld(ID,Database,Object)
    ->  true
    ;   format(atom(MSG), 'Document resource ~s can not be found', [ID]),
        throw(http_reply(not_found(_{'terminus:message' : MSG,
                                     'terminus:object' : ID,
                                     'terminus:status' : 'terminus:failure'})))).

/*
 * try_get_document(ID, Database) is det.
 *
 * Actually has determinism: det + error
 *
 * Gets document as filled frame (JSON-LD) associated with ID
 */
try_get_filled_frame(ID,Database,Object) :-
    (   document_filled_class_frame_jsonld(ID,_{},Database,Object)
    ->  true
    ;   format(atom(MSG), 'Document resource ~s can not be found', [ID]),
        throw(http_reply(not_found(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : MSG,
                                     'terminus:object' : ID})))).

/*
 * try_delete_document(+ID, +Database, -Witnesses) is det.
 *
 * Actually has determinism: det + error
 *
 * Deletes the object associated with ID, and throws an
 * http error otherwise.
 */
try_delete_document(Pre_Doc_ID, Database, Witnesses) :-
    (   collection_descriptor_prefixes(Database.descriptor, Ctx)
    ->  prefix_expand(Pre_Doc_ID,Ctx,Doc_ID)
    ;   format(atom(MSG), 'Document resource ~s could not be expanded', [Pre_Doc_ID]),
        throw(http_reply(not_found(_{'terminus:status' : 'terminus_failure',
                                     'terminus:message' : MSG,
                                     'terminus:object' : Pre_Doc_ID})))),

    (   object_instance_graph(Doc_ID, Database, Document_Graph)
    ->  true
    ;   terminus_databasoe(Terminus_DB),
        Graph_Filter = type_name_filter{ type : instance, names : ["main"]},
        filter_transaction_graph_descriptor(Terminus_DB,Graph_Filter, Document_Graph)
    ),

    (   document_transaction(Database, Transaction_DB, Document_Graph,
                             frame:delete_object(Doc_ID,Transaction_DB),
                             Witnesses)
    ->  true
    ;   format(atom(MSG), 'Document resource ~s could not be deleted', [Doc_ID]),
        throw(http_reply(not_found(_{'terminus:status' : 'terminus_failure',
                                     'terminus:message' : MSG,
                                     'terminus:object' : Doc_ID})))).

/*
 * try_update_document(ID, Doc, Database) is det.
 *
 * Actually has determinism: det + error
 *
 * Updates the object associated with ID, and throws an
 * http error otherwise.
 */
try_update_document(Terminus_DB,Doc_ID, Doc_In, Database, Witnesses) :-
    % if there is no id, we'll use the requested one.
    (   jsonld_id(Doc_In,Doc_ID_Match)
    ->  Doc_In = Doc
    %   This is wrong - we need to have the base path here as well.
    ;   put_dict(Doc_ID,'@id',Doc_In,Doc)),

    (   collection_descriptor_prefixes(Database.descriptor, Ctx),
        get_key_document('@id',Ctx,Doc,Doc_ID_Match)
    ->  true
    ;   format(atom(MSG),'Unable to match object ids ~q and ~q', [Doc_ID, Doc_ID_Match]),
        throw(http_reply(not_found(_{'terminus:message' : MSG,
                                     'terminus:status' : 'terminus:failure'})))),

    (   object_instance_graph(Doc, Database, Document_Graph)
    ->  true
    ;   Graph_Filter = type_name_filter{ type: instance, names : ["main"]},
        filter_transaction_graph_descriptor(Graph_Filter, Terminus_DB, Document_Graph)
    ),

    (   document_transaction(Database, Transaction_DB, Document_Graph,
                             frame:update_object(Doc,Transaction_DB), Witnesses)
    ->  true
    ;   format(atom(MSG),'Unable to update object at Doc_ID: ~q', [Doc_ID]),
        throw(http_reply(not_found(_{'terminus:message' : MSG,
                                     'terminus:status' : 'terminus:failure'})))).

/*
 * try_db_uri(DB,DB_URI) is det.
 *
 * Die if we can't form a document uri.
 */
try_db_uri(DB,DB_URI) :-
    (   config:public_server_url(Server_Name),
        interpolate([Server_Name,'/',DB],DB_URI)
    ->  true
    ;   throw(http_reply(not_found(_{'terminus:message' : 'Database resource can not be found',
                                     'terminus:status' : 'terminus:failure',
                                     'terminus:object' : DB})))).

/*
 * try_doc_uri(DB,Doc,Doc_URI) is det.
 *
 * Die if we can't form a document uri.
 */
try_doc_uri(DB_URI,Doc_ID,Doc_URI) :-
    uri_encoded(path,Doc_ID,Doc_ID_Safe),
    (   interpolate([DB_URI,'/',document, '/',Doc_ID_Safe],Doc_URI)
    ->  true
    ;   format(atom(MSG), 'Document resource ~s can not be constructed in ~s', [DB_URI,Doc_ID]),
        throw(http_reply(not_found(_{'terminus:message' : MSG,
                                     'terminus:status' : 'terminus:failure',
                                     'terminus:object' : DB_URI})))).

/*
 * try_db_graph(+DB:uri,-Database:database) is det.
 *
 * Die if we can't form a graph
 */
try_db_graph(DB_URI,Database) :-
    (   resolve_query_resource(DB_URI, Descriptor)
    ->  open_descriptor(Descriptor,Database)
    ;   format(atom(MSG), 'Resource ~s can not be found', [DB_URI]),
        throw(http_reply(not_found(_{'terminus:message' : MSG,
                                     'terminus:status' : 'terminus:failure',
                                     'terminus:object' : DB_URI})))).

/*
 * try_get_param(Key,Request:request,Value) is det.
 *
 * Get a parameter from the request independent of request variety.
 */
try_get_param(Key,Request,Value) :-
    % GET or POST (but not application/json)
    memberchk(method(post), Request),
    memberchk(multipart(Parts), Request),
    !,
    (   memberchk(Key=Encoded_Value, Parts)
    ->  uri_encoded(query_value, Value, Encoded_Value)
    ;   format(atom(MSG), 'Parameter resource ~q can not be found in ~q', [Key,Parts]),
        throw(http_reply(not_found(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : MSG})))).
try_get_param(Key,Request,Value) :-
    % GET or POST (but not application/json)
    memberchk(method(Method), Request),
    (   memberchk(Method, [get,delete])
    ;   Method = post,
        \+ memberchk(content_type('application/json'), Request)),

    http_parameters(Request, [], [form_data(Data)]),

    (   memberchk(Key=Value,Data)
    ->  true
    ;   format(atom(MSG), 'Parameter resource ~q can not be found in ~q', [Key,Data]),
        throw(http_reply(not_found(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : MSG})))),
    !.
try_get_param(Key,Request,Value) :-
    % POST with JSON package
    memberchk(method(post), Request),
    memberchk(content_type('application/json'), Request),

    (   memberchk(payload(Document), Request)
    ->  true
    ;   format(atom(MSG), 'No JSON payload resource ~q for POST ~q', [Key,Request]),
        throw(http_reply(not_found(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : MSG})))),

    (   Value = Document.get(Key)
    ->  true
    ;   format(atom(MSG), 'Parameter resource ~q can not be found in ~q', [Key,Document]),
        throw(http_reply(not_found(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : MSG})))),
    !.
try_get_param(Key,Request,_Value) :-
    % OTHER with method
    memberchk(method(Method), Request),
    !,

    format(atom(MSG), 'Method ~q has no parameter key transport for key ~q', [Key,Method]),
    throw(http_reply(not_found(_{'terminus:message' : MSG,
                                 'terminus:status' : 'terminus:failure',
                                 'terminus:object' : Key}))).
try_get_param(Key,_Request,_Value) :-
    % Catch all.
    format(atom(MSG), 'Request has no parameter key transport for key ~q', [Key]),
    throw(http_reply(not_found(_{'terminus:status' : 'terminus:failure',
                                 'terminus:message' : MSG}))).

/*
 * get_param_default(Key,Request:request,Value,Default) is semidet.
 *
 * We can fail with this one, so you better do your own checking.
 */
get_param(Key,Request,Value) :-
    % GET or POST (but not application/json)
    memberchk(method(Method), Request),
    memberchk(Method, [get,delete,post]),
    % The agent is not sending a JSON request type
    \+ memberchk(content_type('application/json'), Request),
    !,

    http_parameters(Request, [], [form_data(Data)]),
    memberchk(Key=Value,Data).
get_param(Key,Request,Value) :-
    % POST with JSON package
    memberchk(method(post), Request),
    memberchk(content_type('application/json'), Request),

    memberchk(payload(Document), Request),
    get_dict(Key, Document, Value).


/*
 * try_create_db(DB,DB_URI,Object) is det.
 *
 * Try to create a database and associate resources
 */
try_create_db(DB,Base_Uri) :-
    % create the collection if it doesn't exist
    (   database_exists(DB)
    ->  throw(http_reply(method_not_allowed(_{'terminus:status' : 'terminus:failure',
                                              'terminus:message' : 'Database already exists',
                                              'terminus:method' : 'terminus:create_database'})))
    ;   true),

    (   create_db(DB, Base_Uri)
    ->  true
    ;   format(atom(MSG), 'Database ~s could not be created', [DB]),
        throw(http_reply(not_found(_{'terminus:message' : MSG,
                                     'terminus:status' : 'terminus:failure'})))).


/*
 * try_delete_db(DB_URI) is det.
 *
 * Attempt to delete a database given its URI
 */
try_delete_db(DB) :-
    (   delete_db(DB)
    ->  true
    ;   format(atom(MSG), 'Database ~s could not be destroyed', [DB]),
        throw(http_reply(not_found(_{'terminus:message' : MSG,
                                     'terminus:status' : 'terminus:failure'})))).

/*
 * try_atom_json(Atom,JSON) is det.
 */
try_atom_json(Atom,JSON) :-
    (   atom_json_dict(Atom, JSON, [])
    ->  true
    ;   format(atom(MSG), 'Malformed JSON Object', []),
        % Give a better error code etc. This is silly.
        throw(http_reply(not_found(_{'terminus:status' : 'terminus:failure',
                                     'terminus:message' : MSG,
                                     'terminus:object' : Atom})))).

/*
 * add_payload_to_request(Request:request,JSON:json) is det.
 *
 * Updates request with JSON-LD payload in payload(Document).
 * This should really be done automatically at request time
 * using the endpoint wrappers so we don't forget to do it.
 */
add_payload_to_request(Request,[multipart(Parts)|Request]) :-
    memberchk(method(post), Request),
    memberchk(content_type(ContentType), Request),
    http_parse_header_value(
        content_type, ContentType,
        media(multipart/'form-data', _)
    ),
    !,

    http_read_data(Request, Parts, [on_filename(save_post_file)]).
add_payload_to_request(Request,[payload(Document)|Request]) :-
    member(method(post), Request),
    member(content_type('application/json'), Request),
    !,
    http_read_data(Request, Document, [json_object(dict)]).
add_payload_to_request(Request,Request).

/*
 * save_post_file(In,File_Spec,Options) is det.
 *
 * Saves a temporary octet stream to a file. Used for multipart
 * file passing via POST.
 */
save_post_file(In, file(Filename, File), Options) :-
    option(filename(Filename), Options),
    setup_call_cleanup(
        tmp_file_stream(octet, File, Out),
        copy_stream_data(In, Out),
        close(Out)
    ).

/*
 * Make a collection of all posted files for
 * use in a Context via WOQL's get/3.
 */
collect_posted_files(Request,Files) :-
    memberchk(multipart(Parts), Request),
    !,
    include([_Token=file(_Name,_Storage)]>>true,Parts,Files).
collect_posted_files(_Request,[]).

/*
 * try_class_frame(Class,Database,Frame) is det.
 */
try_class_frame(Class,Database,Frame) :-
    (   class_frame_jsonld(Class,Database,Frame)
    ->  true
    ;   format(atom(MSG), 'Class Frame could not be json-ld encoded for class ~s', [Class]),
        % Give a better error code etc. This is silly.
        throw(http_reply(not_found(_{ 'terminus:message' : MSG,
                                      'terminus:status' : 'terminus:failure',
                                      'terminus:class' : Class})))).

/*
 * try_dump_schema(DB, Request) is det.
 *
 * Write schema to current stream
 */
try_dump_schema(DB, Name, Request) :-
    with_mutex(
        DB,
        (
            try_get_param('terminus:encoding', Request, Encoding),
            (   coerce_literal_string(Encoding, ES),
                atom_string('terminus:turtle',ES)
            ->  with_output_to(
                    string(String),
                    (   current_output(Stream),
                        graph_to_turtle(DB, Name, Stream)
                    )
                ),
                config:public_server_url(SURI),
                write_cors_headers(SURI, DB),
                reply_json(String)
            ;   format(atom(MSG), 'Unimplemented encoding ~s', [Encoding]),
                % Give a better error code etc. This is silly.
                throw(http_reply(method_not_allowed(_{'terminus:message' : MSG,
                                                      'terminus:object' : DB,
                                                      'terminus:status' : 'terminus:failure'})))
            )
        )
    ).

/*
 * try_update_schema(+DB,+Schema_Name,+TTL,-Witnesses) is det.
 *
 */
try_update_schema(DB,Schema_Name,TTL,Witnesses) :-
    coerce_literal_string(Schema_Name, Schema_String),
    atom_string(Schema_Atom, Schema_String),
    coerce_literal_string(TTL, TTLS),
    make_database_from_database_name(DB, Database),
    setup_call_cleanup(
        open_string(TTLS, TTLStream),
        turtle_schema_transaction(Database, Schema_Atom, TTLStream, Witnesses),
        close(TTLStream)
    ).

/*
 * try_get_metadata(+DB_URI,+Name,+TTL,-Witnesses) is det.
 *
 */
/*
try_get_metadata(DB_URI,JSON) :-
    (   db_size(DB_URI,Size)
    ->  true
    ;   Size = 0),

    (   db_modified_datetime(DB_URI,Modified_DT)
    ->  true
    ;   Modified_DT = "1970-01-01T00:00"
    ),

    (   db_created_datetime(DB_URI,Created_DT)
    ->  true
    ;   Created_DT = "1970-01-01T00:00"
    ),

    get_collection_jsonld_context(DB_URI,Ctx),

    JSON = _{'@context' : Ctx,
             '@type' : 'terminus:DatabaseMetadata',
             'terminus:database_modified_time' : _{'@value' : Modified_DT,
                                                   '@type' : 'xsd:dateTime'},
             'terminus:database_created_time' : _{'@value' : Created_DT,
                                                  '@type' : 'xsd:dateTime'},
             'terminus:database_size' : _{'@value' : Size,
                                          '@type' : 'xsd:nonNegativeInteger'}}.
*/