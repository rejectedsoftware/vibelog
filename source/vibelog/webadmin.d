module vibelog.webadmin;

public import vibelog.controller;

import vibelog.config;
import vibelog.post;
import vibelog.user;

import vibe.http.router;
import vibe.web.web;
import std.exception : enforce;
import std.typecons : Nullable;


void registerVibeLogWebAdmin(URLRouter router, VibeLogController controller)
{
	auto websettings = new WebInterfaceSettings;
	websettings.urlPrefix = (controller.settings.siteURL.path ~ controller.settings.adminPrefix).toString();
	router.registerWebInterface(new VibeLogWebAdmin(controller), websettings);
}

/// private
/*private*/ final class VibeLogWebAdmin {
	private {
		VibeLogController m_ctrl;
		VibeLogSettings m_settings;
		string m_subPath;
		string m_config;
	}

	this(VibeLogController controller)
	{
		m_ctrl = controller;
		m_settings = controller.settings;
		m_subPath = (m_settings.siteURL.path ~ m_settings.adminPrefix).toString();
	}

	void getLogin(string redirect = "")
	{
		auto info = AdminInfo(AuthInfo.init, m_settings);
		render!("vibelog.admin.login.dt", info, redirect);
	}

	// the whole admin interface needs authentication
	@auth:

	void get(AuthInfo _auth)
	{
		auto info = AdminInfo(_auth, m_settings);

		render!("vibelog.admin.home.dt", info);
	}

	//
	// Configs
	//

	@path("configs/")
	void getConfigs(AuthInfo _auth)
	{
		enforceAuth(_auth.loginUser.isConfigAdmin());

		auto info = ConfigsInfo(_auth, m_settings);
		info.configs =  m_ctrl.db.getAllConfigs();
		info.activeConfigName = m_settings.configName;

		render!("vibelog.admin.editconfiglist.dt", info);
	}

	@path("configs/:configname/")
	void getConfigEdit(string _configname, AuthInfo _auth)
	{
		enforceAuth(_auth.loginUser.isConfigAdmin());

		auto info = ConfigEditInfo(_auth, m_settings);
		info.config = m_ctrl.db.getConfig(_configname);
		info.globalConfig = m_ctrl.db.getConfig("global", true);

		render!("vibelog.admin.editconfig.dt", info);
	}

	@path("configs/:configname/")
	void postPutConfig(HTTPServerRequest req, string language, string copyrightString, string feedTitle, string feedLink, string feedDescription, string feedImageTitle, string feedImageUrl, string _configname, AuthInfo _auth, string categories = null)
	{
		import std.string;

		enforceAuth(_auth.loginUser.isConfigAdmin());
		Config cfg = m_ctrl.db.getConfig(_configname);
		if( cfg.name == "global" )
			cfg.categories = categories.splitLines();
		else {
			cfg.categories = null;
			foreach( k, v; req.form ){
				if( k.startsWith("category_") )
					cfg.categories ~= k[9 .. $];
			}
		}
		cfg.language = language;
		cfg.copyrightString = copyrightString;
		cfg.feedTitle = feedTitle;
		cfg.feedLink = feedLink;
		cfg.feedDescription = feedDescription;
		cfg.feedImageTitle = feedImageTitle;
		cfg.feedImageUrl = feedImageUrl;
	
		m_ctrl.db.setConfig(cfg);

		redirect(m_subPath ~ "configs/");
	}

	@path("configs/:configname/delete")
	void postDeleteConfig(string _configname, AuthInfo _auth)
	{
		enforceAuth(_auth.loginUser.isConfigAdmin());
		m_ctrl.db.deleteConfig(_configname);
		redirect(m_subPath ~ "configs/");
	}


	//
	// Users
	//

	@path("users/")
	void getUsers(AuthInfo _auth)
	{
		auto info = AdminInfo(_auth, m_settings);

		render!("vibelog.admin.edituserlist.dt", info);
	}

	@path("users/:username/")
	void getUserEdit(string _username, AuthInfo _auth)
	{
		auto info = UserEditInfo(_auth, m_settings);

		info.globalConfig = m_ctrl.db.getConfig("global", true);
		info.user = m_ctrl.db.getUserByName(_username);

		render!("vibelog.admin.edituser.dt", info);
	}

	@path("users/:username/")
	void postPutUser(string id, string username, string password, string name, string email, string passwordConfirmation, Nullable!string oldPassword, string _username, HTTPServerRequest req, AuthInfo _auth)
	{
		import vibe.crypto.passwordhash;
		import vibe.data.bson : BsonObjectID;
		import std.algorithm.searching : startsWith;

		User usr;
		if( id.length > 0 ){
			enforce(_auth.loginUser.isUserAdmin() || username == _auth.loginUser.username,
				"You can only change your own account.");
			usr = m_ctrl.db.getUser(BsonObjectID.fromHexString(id));
			enforce(usr.username == username, "Cannot change the user name!");
		} else {
			enforce(_auth.loginUser.isUserAdmin(), "You are not allowed to add users.");
			usr = new User;
			usr.username = username;
			foreach (u; _auth.users)
				enforce(u.username != usr.username, "A user with the specified user name already exists!");
		}
		enforce(password == passwordConfirmation, "Passwords do not match!");

		usr.name = name;
		usr.email = email;

		if (password.length) {
			enforce(_auth.loginUser.isUserAdmin() || testSimplePasswordHash(oldPassword, usr.password), "Old password does not match.");
			usr.password = generateSimplePasswordHash(password);
		}

		if (_auth.loginUser.isUserAdmin()) {
			usr.groups = null;
			foreach( k, v; req.form ){
				if( k.startsWith("group_") )
					usr.groups ~= k[6 .. $];
			}

			usr.allowedCategories = null;
			foreach( k, v; req.form ){
				if( k.startsWith("category_") )
					usr.allowedCategories ~= k[9 .. $];
			}
		}

		if( id.length > 0 ){
			m_ctrl.db.modifyUser(usr);
		} else {
			usr._id = m_ctrl.db.addUser(usr);
		}

		if (_auth.loginUser.isUserAdmin()) redirect(m_subPath~"users/");
		else redirect(m_subPath);
	}

	@path("users/:username/delete")
	void postDeleteUser(string _username, AuthInfo _auth)
	{
		enforceAuth(_auth.loginUser.isUserAdmin(), "You are not authorized to delete users!");
		enforce(_auth.loginUser.username != _username, "Cannot delete the own user account!");
		foreach (usr; _auth.users)
			if (usr.username == _username) {
				m_ctrl.db.deleteUser(usr._id);
				redirect(m_subPath ~ "users/");
				return;
			}
		
		// fall-through (404)
	}

	@path("users/")
	void postAddUser(string username, AuthInfo _auth)
	{
		enforceAuth(_auth.loginUser.isUserAdmin(), "You are not authorized to add users!");
		if (username !in _auth.users) {
			auto u = new User;
			u.username = username;
			m_ctrl.db.addUser(u);
		}
		redirect(m_subPath ~ "users/" ~ username ~ "/");
	}

	//
	// Posts
	//

	@path("posts/")
	void getPosts(AuthInfo _auth)
	{
		auto info = PostsInfo(_auth, m_settings);
		m_ctrl.db.getAllPosts(0, (size_t idx, Post post){
			if (_auth.loginUser.isPostAdmin() || post.author == _auth.loginUser.username
				|| _auth.loginUser.mayPostInCategory(post.category))
			{
				info.posts ~= post;
			}
			return true;
		});

		render!("vibelog.admin.editpostslist.dt", info);
	}

	@path("make_post")
	void getMakePost(AuthInfo _auth, string _error = null)
	{
		auto info = PostEditInfo(_auth, m_settings);
		info.globalConfig = m_ctrl.db.getConfig("global", true);
		info.error = _error;

		render!("vibelog.admin.editpost.dt", info);
	}

	@auth @errorDisplay!getMakePost
	void postMakePost(bool isPublic, bool commentsAllowed, string author,
		string date, string category, string slug, string headerImage, string header, string subHeader,
		string content, string filters, AuthInfo _auth)
	{
		postPutPost(null, isPublic, commentsAllowed, author, date, category, slug, headerImage, header, subHeader, content, filters, null, _auth);
	}

	@path("posts/:postname/")
	void getEditPost(string _postname, AuthInfo _auth, string _error = null)
	{
		auto info = PostEditInfo(_auth, m_settings);
		info.globalConfig = m_ctrl.db.getConfig("global", true);
		info.post = m_ctrl.db.getPost(_postname);
		info.files = m_ctrl.db.getFiles(_postname);
		info.error = _error;
		render!("vibelog.admin.editpost.dt", info);
	}

	@path("posts/:postname/delete")
	void postDeletePost(string id, string _postname, AuthInfo _auth)
	{
		import vibe.data.bson : BsonObjectID;
		// FIXME: check permissons!
		auto bid = BsonObjectID.fromHexString(id);
		m_ctrl.db.deletePost(bid);
		redirect(m_subPath ~ "posts/");
	}

	@path("posts/:postname/") @errorDisplay!getEditPost
	void postPutPost(string id, bool isPublic, bool commentsAllowed, string author,
		string date, string category, string slug, string headerImage, string header, string subHeader,
		string content, string filters, string _postname, AuthInfo _auth)
	{
		import vibe.data.bson : BsonObjectID;

		Post p;
		if( id.length > 0 ){
			p = m_ctrl.db.getPost(BsonObjectID.fromHexString(id));
			enforce(_postname == p.name, "URL does not match the edited post!");
		} else {
			p = new Post;
			p.category = "general";
			p.date = Clock.currTime().toUTC();
		}
		enforce(_auth.loginUser.mayPostInCategory(category), "You are now allowed to post in the '"~category~"' category.");

		p.isPublic = isPublic;
		p.commentsAllowed = commentsAllowed;
		p.author = author;
		p.date = SysTime.fromSimpleString(date);
		p.category = category;
		p.slug = slug.length ? slug : header.length ? makeSlugFromHeader(header) : id;
		p.headerImage = headerImage;
		p.header = header;
		p.subHeader = subHeader;
		p.content = content;
		import std.array : split;
		p.filters = filters.split();

		enforce(!m_ctrl.db.hasPost(p.slug) || m_ctrl.db.getPost(p.slug).id == p.id, "Post slug is already used for another article.");

		if( id.length > 0 )
		{
			m_ctrl.db.modifyPost(p);
			_postname = p.name;
		}
		else
		{
			p.id = m_ctrl.db.addPost(p);
		}
		redirect(m_subPath~"posts/");
	}

	@path("posts/:postname/files/:filename/delete") @errorDisplay!getEditPost
	void postDeleteFile(string _postname, string _filename, AuthInfo _auth)
	{
		m_ctrl.db.removeFile(_postname, _filename);
		redirect("../../");
	}

	@path("posts/:postname/files/") @errorDisplay!getEditPost
	void postUploadFile(string _postname, HTTPServerRequest req, AuthInfo _auth)
	{
		import vibe.core.file;
		import vibe.stream.operations : readAll;

import vibe.core.log;
logInfo("FILES %s %s", req.files.length, req.files.getAll("files"));
		foreach (f; req.files.byValue) {
logInfo("FILE %s", f.filename.name);
			auto fil = openFile(f.tempPath, FileMode.read);
			scope (exit) fil.close();
			m_ctrl.db.addFile(_postname, f.filename.name, fil.readAll());
		}
		redirect("../");
	}

	private enum auth = before!performAuth("_auth");

	private AuthInfo performAuth(HTTPServerRequest req, HTTPServerResponse res)
	{
		import vibe.inet.webform : formEncode;

		string uname = req.session ? req.session.get("vibelog.loggedInUser", "") : "";
		User[string] users = m_ctrl.db.getAllUsers();
		auto pu = uname in users;
		if (pu is null) {
			redirect(m_subPath ~ "login?"~formEncode(["redirect": req.path]));
			return AuthInfo.init;
		}
		enforceHTTP(pu !is null, HTTPStatus.forbidden, "Not authorized to access this page.");
		return AuthInfo(*pu, users);
	}

	mixin PrivateAccessProxy;
}

struct AdminInfo
{
	import vibelog.info : VibeLogInfo;
	VibeLogInfo vli;
	alias vli this;

	User loginUser;
	User[string] users;
	InetPath rootPath, managePath;
	string loginError;

	import vibelog.settings : VibeLogSettings;
	this(AuthInfo auth, VibeLogSettings settings)
	{
		vli = VibeLogInfo(settings);
		loginUser = auth.loginUser;
		users = auth.users;
		this.settings = settings;
		rootPath = settings.siteURL.path;
		managePath = rootPath ~ settings.adminPrefix;
	}
}

enum string mixAdminInfo = q{AdminInfo ai; alias ai this;};
enum string mixInitAdminInfo = q{ai = AdminInfo(auth, settings);};

struct PostEditInfo
{
	mixin(mixAdminInfo);

	import vibelog.config : Config;
	Config globalConfig;

	import vibelog.post : Post;
	Post post;

	string[] files;
	string error;

	import vibelog.settings : VibeLogSettings;
	this(AuthInfo auth, VibeLogSettings settings)
	{
		mixin(mixInitAdminInfo);
	}
}

struct ConfigEditInfo
{
	mixin(mixAdminInfo);

	Config config;
	Config globalConfig;

	import vibelog.settings : VibeLogSettings;
	this(AuthInfo auth, VibeLogSettings settings, Config config, Config globalConfig)
	{
		this(auth, settings);
		this.config = config;
		this.globalConfig = globalConfig;
	}

	this(AuthInfo auth, VibeLogSettings settings)
	{
		mixin(mixInitAdminInfo);
	}
}

struct ConfigsInfo
{
	mixin(mixAdminInfo);

	import vibelog.config : Config;
	Config[] configs;
	string activeConfigName;

	import vibelog.settings : VibeLogSettings;
	this(AuthInfo auth, VibeLogSettings settings, Config[] configs, string activeConfigName)
	{
		this(auth, settings);
		this.configs = configs;
		this.activeConfigName = activeConfigName;
	}
	this(AuthInfo auth, VibeLogSettings settings)
	{
		mixin(mixInitAdminInfo);
	}
}

struct UserEditInfo
{
	mixin(mixAdminInfo);

	import vibelog.config : Config;
	Config globalConfig;

	import vibelog.user : User;
	User user;

	import vibelog.settings : VibeLogSettings;
	this(AuthInfo auth, VibeLogSettings settings)
	{
		mixin(mixInitAdminInfo);
	}
}

struct PostsInfo
{
	mixin(mixAdminInfo);

	import vibelog.post : Post;
	Post[] posts;

	import vibelog.settings : VibeLogSettings;
	this(AuthInfo auth, VibeLogSettings settings)
	{
		mixin(mixInitAdminInfo);
	}
}

private struct AuthInfo {
	User loginUser;
	User[string] users;
}

private void enforceAuth(bool cond, lazy string message = "Not authorized to perform this action!")
{
	if (!cond) throw new HTTPStatusException(HTTPStatus.forbidden, message);
}