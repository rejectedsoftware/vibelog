import vibe.http.router;
import vibe.http.server;

import vibelog.controller;
import vibelog.web;
import vibelog.webadmin;

shared static this()
{
	//setLogLevel(LogLevel.Trace);

	auto router = new URLRouter;

	auto blogsettings = new VibeLogSettings;
	blogsettings.configName = "example";
	blogsettings.siteURL = URL("http://localhost:8080/");
	blogsettings.blogName = "VibeLog";
	blogsettings.blogDescription = "Publishing software utilizing the vibe.d framework";

	auto ctrl = new VibeLogController(blogsettings);
	router.registerVibeLogWeb(ctrl);
	router.registerVibeLogWebAdmin(ctrl);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	listenHTTP(settings, router);
}
