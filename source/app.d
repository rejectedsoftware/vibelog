import vibe.http.router;
import vibe.http.server;

import vibelog.dbcontroller;
import vibelog.settings;
import vibelog.web;

shared static this()
{
	//setLogLevel(LogLevel.Trace);

	auto router = new URLRouter;

	auto blogsettings = new VibeLogSettings;
	blogsettings.configName = "vibelog";
	blogsettings.siteUrl = URL("http://localhost:8080/");
	auto ctrl = new DBController(blogsettings);

	router.registerVibeLogWeb(ctrl, blogsettings);
	
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	listenHTTP(settings, router);
}
