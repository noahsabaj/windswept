# Getting Started
It's pretty easy to get started with creating your own schema with Windswept. It requires a bit of bootstrapping if you're starting from scratch, but you should quickly be on your way to developing your schema after following one of the below sections in this guide.

# Installing the framework
Before you start working on your schema, you'll need to install Windswept onto your server. The exact instructions will vary based on your server provider, or if you're hosting the server yourself.

You'll need to download the framework from [GitHub](https://github.com/noahsabaj/windswept) into a folder called `windswept`. This folder goes into your server's `gamemodes` folder at `garrysmod/gamemodes/windswept`. That's it! The framework is now installed onto your server. Of course, you'll need to restart your server after installing the framework and a schema.

# MySQL usage
By default, Windswept will use SQLite (which is built into Garry's Mod) to store player/character data. This requires no configuration and will work "out of the box" after installing and will be fine for most server owners. However, you might want to connect your database to your website or use multiple servers with one database - this will require the usage of an external database accessible elsewhere. This will require the use of a MySQL server. Some server providers will provide you with a MySQL database for free to use with your server.

## Installing
Windswept uses the [MySQLOO](https://github.com/FredyH/MySQLOO) library to connect to MySQL databases. You'll need to follow the instructions for installing that library onto your server before continuing. In a nutshell, you need to make sure `gmsv_mysqloo_win32.dll` or `gmsv_mysqloo_linux.dll` (depending on your server's operating system) is in the `garrysmod/lua/bin` folder. 

In older versions of MySQLOO, you previously required a .dll called `libmysql.dll` to place in your `root` server folder, where `srcds`/`srcds_linux` was stored. Newer versions of MySQLOO no longer require this.

## Configuring
Now that you've installed MySQLOO, you need to tell Windswept that you want to connect to an external MySQL database instead of using SQLite. This requires creating a `windswept.yml` configuration file in the `garrysmod/gamemodes/windswept` folder. There is an example one already made for you called `windswept.example.yml` that you can copy and rename to `windswept.yml`.

The first thing you'll need to change is the `adapter` entry so that it says `mysqloo`. Next is to change the other entries to match your database's connection information. Here is an example of what your `windswept.yml` should look like:

```
database:
  adapter: "mysqloo"
  hostname: "myexampledatabase.com"
  username: "myusername"
  password: "mypassword"
  database: "windswept"
  port: 3306
```

The `hostname` field can either be a domain name (like `myexampledatabase.com`) or an IP address (`123.123.123.123`). If you don't know what the `port` field should be, simply leave it as the default `3306`; this is the default port for MySQL database connections. The `database` field is the name of the database that you've created for Windswept. Note that it does not need to be `windswept`, it can be whatever you'd like.

Another important thing to note about this configuration file is that you **must** indent with **two spaces only**. `database` should not have any spacing before it, and all other entries must have two spaces before them. Failing to ensure this will make the configuration file fail to load.

# Starting from scratch (Intermediate)
You can always create the gamemode files yourself if you'd like (although we suggest the skeleton schema in general). In general, a schema is a gamemode that is derived from `windswept` and automatically loads `schema/sh_schema.lua`. You shouldn't have your schema files outside of the `schema` folder. The files you'll need are as follows:

`gamemode/init.lua`
```
AddCSLuaFile("cl_init.lua")
DeriveGamemode("windswept")
```

`gamemode/cl_init.lua`
```
DeriveGamemode("windswept")
```

`schema/sh_schema.lua`
```
Schema.name = "My Schema"
Schema.author = "me!"
Schema.description = "My awesome schema."

-- include your other schema files
ws.util.Include("cl_schema.lua")
ws.util.Include("sv_schema.lua")
-- etc.
```
