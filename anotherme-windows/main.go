package main

import (
	"fmt"
)

func main() {
	app := NewApp()

	// TODO: Replace with Wails v2 initialization when wails dependency is added.
	// The Wails entry point will look like:
	//
	//   err := wails.Run(&options.App{
	//       Title:     "AnotherMe",
	//       Width:     1200,
	//       Height:    800,
	//       MinWidth:  800,
	//       MinHeight: 600,
	//       AssetServer: &assetserver.Options{
	//           Assets: assets,
	//       },
	//       OnStartup:  app.startup,
	//       OnShutdown: app.shutdown,
	//       Bind: []interface{}{
	//           app,
	//       },
	//   })

	// For now, just verify the app initializes correctly.
	fmt.Println("AnotherMe Windows - initializing...")
	app.startup(nil)
	defer app.shutdown(nil)
	fmt.Println("AnotherMe Windows - ready (Wails UI not yet integrated)")

	// When Wails is integrated, wails.Run() will block here.
	// Return naturally so that deferred shutdown runs.
}
