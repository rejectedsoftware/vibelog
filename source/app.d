import vibe.d;

import vibelog.vibelog;

static this()
{
	//setLogLevel(LogLevel.Trace);

	auto router = new URLRouter;

	auto blogsettings = new VibeLogSettings;
	blogsettings.configName = "vibelog";
	blogsettings.siteUrl = URL("http://localhost:8080/");
	registerVibeLog(blogsettings, router);
	
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	listenHTTP(settings, router);
}
