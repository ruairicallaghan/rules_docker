package main

import (
	"flag"
	"io/ioutil"
	"log"
	"os"
	// "github.com/bazelbuild/rules_docker/container/go/pkg/compat"
	"github.com/bazelbuild/rules_docker/container/go/pkg/utils"
)

var (
	stampInfoFile utils.ArrayStringFlags
	dest          = flag.String("dest", "", "The destination location of the tag file to write to.")
)

func main() {

	flag.Var(&stampInfoFile, "stamp-info-file", "The list of paths to the stamp info files used to substitute supported attribute when a python format placeholder is provivided in dst, e.g., {BUILD_USER}.")
	flag.Parse()

	// stamper, err := compat.NewStamper(stampInfoFile)
	// if err != nil {
	// 	log.Fatalf("Failed to initialize the stamper: %v", err)
	// }

	// dst := "gcr.io/{STABLE_PROJECT_ID}/examples/simple-deployment:{STABLE_COMMIT_SHA}"
	// stamped := stamper.Stamp(dst)
	// if stamped != dst {
	// 	log.Printf("Destination %s was resolved to %s after stamping.", dst, stamped)
	// }

	// if err := ioutil.WriteFile(*dest, []byte(stamped), os.ModePerm); err != nil {
	// 	log.Fatalf("Error outputting digest file to %s: %v", *dest, err)
	// }

	stamped := "stampMe"
	out := "examples/simple-deployment/image.push.stamp"
	if err := ioutil.WriteFile(out, []byte(stamped), os.ModePerm); err != nil {
		log.Fatalf("Error outputting digest file to %s: %v", out, err)
	}

}
