vibelog
=======

A fast and simple embeddable blog for multi-site authoring

Beware that the base package will provide a very plain blog layout. There is no styling or advanced layouting. See the [vibe.d blog](http://vibed.org/blog/posts/new-website-has-got-vibe) for a slightly styled example.


Main features
-------------

 - Multi-site configurations
 - Multi-user management with access restriction
 - Directly embeddable in vibe.d sites
 - RSS feed
 - User comments
 - Customizable template based layout
 - Heading, sub heading, header image, automatic post slug creation

Prerequisites
-------------

VibeLog needs [dub](https://github.com/rejectedsoftware/dub/) and [MongoDB](http://www.mongodb.org/) installed.

Running a simple stand-alone blog
---------------------------------

1. Clone vibelog

		$ git clone git://github.com/rejectedsoftware/vibelog.git

2. Compile and run

		$ cd vibelog
		$ dub run

The blog is now accessible at <http://127.0.0.1:8080/>.


Embedding VibeLog into your own application
-------------------------------------------

1. Create a new project:

		$ dub init my-blog
		$ cd my-blog

2. Edit package.json and add the following entries to the "dependencies" section:

		"vibelog": ">=0.0.9"

3. Edit source/app.d:

	```
	import vibe.d;
	import vibelog.vibelog;

	static this()
	{
		auto router = new UrlRouter;

		auto blogsettings = new VibeLogSettings;
		blogsettings.configName = "vibelog";
		blogsettings.basePath = "/";
		registerVibeLog(blogsettings, router);

		router.get("*", serveStaticFiles("./public"));

		auto settings = new HttpServerSettings;
		settings.port = 8080;
		listenHttp(settings, router);
	}
	```

	If you want to run multiple blogs on the same database, you should choose a meaningful configuration name instead of "vibelog". Each blog should have its own configuration name.

4. Start the application (dub will automatically download vibelog and vibe.d as dependencies)

		$ dub run

You will probably also want to copy the views/layout.dt file to your own project and modify it to your needs (e.g. by adding a style sheet). The blog is accessible at <http://127.0.0.1:8080/blog/>.


Setting everything up
---------------------

1. Go to the management page on your blog (e.g. <http://127.0.0.1:8080/blog/manage>). Use username `admin` and password `admin` when logging in for the first time.

2. Open the user management page and create a new user. Be sure to make the new user an administrator. The `admin` user will be disabled afterwards.

3. Open the configuration management page and edit the `global` configuration. You can add categories by entering them into the first field, line by line. Category names must not contain spaces.

4. Now you may edit the active configuration (`example`) and check the categories that should be included on the blog.


Posting articles
----------------

1. Click on `New post` on the management page.

2. Fill out the information, including any text filters (currently there's only Markdown, enabled by default).

4. Click on `Create post` to post or the `Preview` checkbox to see what your post would look like.
