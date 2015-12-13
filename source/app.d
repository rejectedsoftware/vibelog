import vibe.http.router;
import vibe.http.server;

import vibelog.controller;
import vibelog.web;
import vibelog.webadmin;

shared static this()
{
	//setLogLevel(LogLevel.Trace);

	auto router = new URLRouter;

	auto blogSettings = new VibeLogSettings;
	blogSettings.configName = "example";
	blogSettings.siteURL = URL("http://localhost:8080/blog/sub/");
	blogSettings.blogName = "VibeLog";
	blogSettings.blogDescription = "Publishing software utilizing the vibe.d framework";

	auto ctrl = new VibeLogController(blogSettings);
	router.registerVibeLogWeb(ctrl);
	router.registerVibeLogWebAdmin(ctrl);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	listenHTTP(settings, router);
}
