module vibelog.webadmin;

import vibelog.dbcontroller;
import vibelog.settings;

import vibe.http.router;
import vibe.web.web;
import std.exception : enforce;

void registerVibeLogWebAdmin(URLRouter router, DBController ctrl, VibeLogSettings settings)
{
	auto websettings = new WebInterfaceSettings;
	websettings.urlPrefix = (settings.siteURL.path ~ settings.adminPrefix).toString();
	router.registerWebInterface(new VibeLogWebAdmin(ctrl, settings), websettings);
}

private final class VibeLogWebAdmin {
	private {
		DBController m_ctrl;
		VibeLogSettings m_settings;
		string m_subPath;
		string m_config;
	}

	this(DBController ctrl, VibeLogSettings settings)
	{
		m_ctrl = ctrl;
		m_settings = settings;
		m_subPath = (settings.siteURL.path ~ settings.adminPrefix).toString();
	}

	// the whole admin interface needs authentication
	@auth:

	void get(AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		render!("vibelog.admin.home.dt", users, loginUser);
	}

	//
	// Configs
	//

	@path("configs/")
	void getConfigs(AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		enforceAuth(loginUser.isConfigAdmin());
		Config[] configs = m_ctrl.getAllConfigs();
		auto activeConfig = m_settings.configName;
		render!("vibelog.admin.editconfiglist.dt", loginUser, configs, activeConfig);
	}

	@path("configs/:configname/")
	void getConfigEdit(string _configname, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		auto globalConfig = m_ctrl.getConfig("global", true);
		enforceAuth(loginUser.isConfigAdmin());
		Config config = m_ctrl.getConfig(_configname);
		render!("vibelog.admin.editconfig.dt", loginUser, globalConfig, config);
	}

	@path("configs/:configname/")
	void postPutConfig(HTTPServerRequest req, string language, string copyrightString, string feedTitle, string feedLink, string feedDescription, string feedImageTitle, string feedImageUrl, string _configname, AuthInfo _auth, string categories = null)
	{
		import std.string;

		auto loginUser = _auth.loginUser;
		enforceAuth(loginUser.isConfigAdmin());
		Config cfg = m_ctrl.getConfig(_configname);
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
	
		m_ctrl.setConfig(cfg);

		redirect(m_subPath ~ "configs/");
	}

	@path("configs/:configname/delete")
	void postDeleteConfig(string _configname, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		enforceAuth(loginUser.isConfigAdmin());
		m_ctrl.deleteConfig(_configname);
		redirect(m_subPath ~ "configs/");
	}


	//
	// Users
	//

	@path("users/")
	void getUsers(AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		render!("vibelog.admin.edituserlist.dt", loginUser, users);
	}

	@path("users/:username/")
	void getUserEdit(string _username, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		auto globalConfig = m_ctrl.getConfig("global", true);
		User user = m_ctrl.getUser(_username);
		render!("vibelog.admin.edituser.dt", loginUser, globalConfig, user);
	}

	@path("users/:username/")
	void postPutUser(string id, string username, string password, string name, string email, string passwordConfirmation, Nullable!string oldPassword, string _username, HTTPServerRequest req, AuthInfo _auth)
	{
		import vibe.crypto.passwordhash;
		import vibe.data.bson : BsonObjectID;

		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		User usr;
		if( id.length > 0 ){
			enforce(loginUser.isUserAdmin() || username == loginUser.username,
				"You can only change your own account.");
			usr = m_ctrl.getUser(BsonObjectID.fromHexString(id));
			enforce(usr.username == username, "Cannot change the user name!");
		} else {
			enforce(loginUser.isUserAdmin(), "You are not allowed to add users.");
			usr = new User;
			usr.username = username;
			foreach( u; users )
				enforce(u.username != usr.username, "A user with the specified user name already exists!");
		}
		enforce(password == passwordConfirmation, "Passwords do not match!");

		usr.name = name;
		usr.email = email;

		if (password.length) {
			enforce(loginUser.isUserAdmin() || testSimplePasswordHash(oldPassword, usr.password), "Old password does not match.");
			usr.password = generateSimplePasswordHash(password);
		}

		if( loginUser.isUserAdmin() ){
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
			m_ctrl.modifyUser(usr);
		} else {
			usr._id = m_ctrl.addUser(usr);
		}

		if( loginUser.isUserAdmin() ) redirect(m_subPath~"users/");
		else redirect(m_subPath);
	}

	@path("users/:username/delete")
	void postDeleteUser(string _username, AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		enforceAuth(loginUser.isUserAdmin(), "You are not authorized to delete users!");
		enforce(loginUser.username != _username, "Cannot delete the own user account!");
		foreach( usr; users )
			if (usr.username == _username) {
				m_ctrl.deleteUser(usr._id);
				redirect(m_subPath ~ "users/");
				return;
			}
		
		// fall-through (404)
	}

	@path("users/")
	void postAddUser(string username, AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		enforceAuth(loginUser.isUserAdmin(), "You are not authorized to add users!");
		if (username !in users) {
			auto u = new User;
			u.username = username;
			m_ctrl.addUser(u);
		}
		redirect(m_subPath ~ "users/" ~ username ~ "/");
	}

	//
	// Posts
	//

	@path("posts/")
	void getPosts(AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		Post[] posts;
		m_ctrl.getAllPosts(0, (size_t idx, Post post){
			if( loginUser.isPostAdmin() || post.author == loginUser.username
				|| loginUser.mayPostInCategory(post.category) )
			{
				posts ~= post;
			}
			return true;
		});
		render!("vibelog.admin.editpostslist.dt", users, loginUser, posts);
	}

	void getMakePost(AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		auto globalConfig = m_ctrl.getConfig("global", true);
		Post post;
		Comment[] comments;
		render!("vibelog.admin.editpost.dt", users, loginUser, globalConfig, post, comments);
	}

	@auth
	void postMakePost(bool isPublic, bool commentsAllowed, string author,
		string date, string category, string slug, string headerImage, string header, string subHeader,
		string content, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		postPutPost(null, isPublic, commentsAllowed, author, date, category, slug, headerImage, header, subHeader, content, null, _auth);
	}

	@path("posts/:postname/")
	void getEditPost(string _postname, AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		auto globalConfig = m_ctrl.getConfig("global", true);
		auto post = m_ctrl.getPost(_postname);
		auto comments = m_ctrl.getComments(post.id, true);
		render!("vibelog.admin.editpost.dt", users, loginUser, globalConfig, post, comments);
	}

	@path("posts/:postname/delete")
	void postDeletePost(string id, string _postname, AuthInfo _auth)
	{
		import vibe.data.bson : BsonObjectID;
		// FIXME: check permissons!
		auto bid = BsonObjectID.fromHexString(id);
		m_ctrl.deletePost(bid);
		redirect(m_subPath ~ "posts/");
	}

	@path("posts/:postname/set_comment_public")
	void postSetCommentPublic(string id, string _postname, bool public_, AuthInfo _auth)
	{
		import vibe.data.bson : BsonObjectID;
		// FIXME: check permissons!
		auto bid = BsonObjectID.fromHexString(id);
		m_ctrl.setCommentPublic(bid, public_);
		redirect(m_subPath ~ "posts/"~_postname~"/edit");
	}

	@path("posts/:postname/")
	void postPutPost(string id, bool isPublic, bool commentsAllowed, string author,
		string date, string category, string slug, string headerImage, string header, string subHeader,
		string content, string _postname, AuthInfo _auth)
	{
		import vibe.data.bson : BsonObjectID;

		auto loginUser = _auth.loginUser;
		Post p;
		if( id.length > 0 ){
			p = m_ctrl.getPost(BsonObjectID.fromHexString(id));
			enforce(_postname == p.name, "URL does not match the edited post!");
		} else {
			p = new Post;
			p.category = "default";
			p.date = Clock.currTime().toUTC();
		}
		enforce(loginUser.mayPostInCategory(category), "You are now allowed to post in the '"~category~"' category.");

		p.isPublic = isPublic;
		p.commentsAllowed = commentsAllowed;
		p.author = author;
		p.date = SysTime.fromSimpleString(date);
		p.category = category;
		p.slug = slug.length ? slug : makeSlugFromHeader(header);
		p.headerImage = headerImage;
		p.header = header;
		p.subHeader = subHeader;
		p.content = content;

		enforce(!m_ctrl.hasPost(p.slug) || m_ctrl.getPost(p.slug).id == p.id, "Post slug is already used for another article.");

		if( id.length > 0 ){
			m_ctrl.modifyPost(p);
			_postname = p.name;
		} else {
			p.id = m_ctrl.addPost(p);
		}
		redirect(m_subPath~"posts/");
	}

	protected enum auth = before!performAuth("_auth");

	protected AuthInfo performAuth(HTTPServerRequest req, HTTPServerResponse res)
	{
		import vibe.crypto.passwordhash;
		import vibe.http.auth.basic_auth;

		User[string] users = m_ctrl.getAllUsers();
		bool testauth(string user, string password)
		{
			auto pu = user in users;
			if( pu is null ) return false;
			return testSimplePasswordHash(pu.password, password);
		}
		string username = performBasicAuth(req, res, "VibeLog admin area", &testauth);
		auto pusr = username in users;
		assert(pusr, "Authorized with unknown username !?");
		return AuthInfo(*pusr, users);
	}

	mixin PrivateAccessProxy;
}

private struct AuthInfo {
	User loginUser;
	User[string] users;
}

private void enforceAuth(bool cond, lazy string message = "Not authorized to perform this action!")
{
	if (!cond) throw new HTTPStatusException(HTTPStatus.forbidden, message);
}