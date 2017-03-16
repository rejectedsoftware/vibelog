module vibelog.internal.diskuto;

import vibelog.controller;
import vibelog.user;

import diskuto.backend : StoredComment;
import diskuto.web : DiskutoWeb, registerDiskutoWeb;
import diskuto.settings : DiskutoSettings;
import diskuto.userstore : StoredUser, DiskutoUserStore;
import diskuto.backends.mongodb;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest;
import std.typecons : Nullable;

DiskutoWeb registerDiskuto(URLRouter router, VibeLogController ctrl)
{
	auto dsettings = new DiskutoSettings;
	dsettings.resourcePath = "../diskuto/public";
	dsettings.backend = ctrl.diskuto;
	dsettings.userStore = new UserStore(ctrl);
	return router.registerDiskutoWeb(dsettings);
}

private final class UserStore : DiskutoUserStore {
	private {
		VibeLogController m_ctrl;
	}

	this(VibeLogController ctrl)
	{
		m_ctrl = ctrl;
	}

	override Nullable!StoredUser getLoggedInUser(HTTPServerRequest req)
	{
		return Nullable!StoredUser.init;
	}

	override Nullable!StoredUser getUserForEmail(string email)
	@trusted {
		try return Nullable!StoredUser(toStoredUser(m_ctrl.db.getUserByEmail(email)));
		catch (Exception e) { return Nullable!StoredUser.init; }
	}

	private StoredUser toStoredUser(User usr)
	@safe {
		StoredUser ret;
		ret.id = "vibelog-" ~ () @trusted { return usr._id.toString(); } ();
		ret.name = usr.name;
		ret.email = usr.email;
		ret.isModerator = true; // FIXME: only for "allowedCategories"!
		return ret;
	}
}
