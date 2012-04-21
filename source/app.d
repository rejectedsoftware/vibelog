import vibe.d;

import vibelog.vibelog;

static this()
{
	//setLogLevel(LogLevel.Trace);

	auto router = new UrlRouter;

	auto blogsettings = new VibeLogSettings;
	blogsettings.configName = "vibelog";
	blogsettings.basePath = "/";
	registerVibeLog(blogsettings, router);
	
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	listenHttp(settings, router);
}
