#!/usr/bin/env bash
#Ref: https://github.com/ValYouW/tflite-dist/blob/master/build-android.sh
set -e

function log() {
	echo "-->> $1"
}

function rmdir() {
	if [ -d $1 ]; then
		log "Removing folder $1"
		rm -rf $1
	fi
}

function collectHeaders() {
	log "Collecting headers..."
	cd $TF_DIR/tensorflow
	rm -f headers.tar
	find ./lite -name "*.h" | tar -cf headers.tar -T -
	if [ ! -f headers.tar ]; then
		log "headers.tar not created not error given"
		exit 1
	fi

	mv headers.tar $DIST_DIR
	cd $DIST_DIR
	mkdir -p include/tensorflow
	tar xvf headers.tar -C include/tensorflow
	rm headers.tar

	log "Copy absl headers"
	cd $TF_DIR/bazel-tensorflow/external/com_google_absl
	find ./absl -name "*.h" | tar -cf headers.tar -T -
	if [ ! -f headers.tar ]; then
		log "headers.tar not created not error given"
		exit 1
	fi
	mv headers.tar $DIST_DIR
	cd $DIST_DIR
	tar xvf headers.tar -C include
	rm headers.tar

	log "Copy flatbuffers headers..."
	mkdir -p include/flatbuffers
	cp $TF_DIR/bazel-tensorflow/external/flatbuffers/include/flatbuffers/* include/flatbuffers/
}

function buildArch() {
	log "Building for $1 --> $2"
	cd $TF_DIR

	bazel build //tensorflow/lite:libtensorflowlite.so --config=$1 --cxxopt='--std=c++11' -c opt
	bazel build //tensorflow/lite/c:libtensorflowlite_c.so --config=$1 -c opt
	bazel build //tensorflow/lite/delegates/gpu:libtensorflowlite_gpu_delegate.so -c opt --config $1 --copt -Os --copt -DTFLITE_GPU_BINARY_RELEASE --copt -s --strip always

	mkdir -p $DIST_DIR/libs/$2

	cp bazel-bin/tensorflow/lite/libtensorflowlite.so $DIST_DIR/libs/$2/
	cp bazel-bin/tensorflow/lite/c/libtensorflowlite_c.so $DIST_DIR/libs/$2/
	cp bazel-bin/tensorflow/lite/delegates/gpu/libtensorflowlite_gpu_delegate.so $DIST_DIR/libs/$2/
}

# The order of these two should match
ARCHS=("android_arm64" "android_x86_64")
ABIS=("arm64-v8a" "x86_64")

DIST_DIR=`dirname ${BASH_SOURCE[0]}`
DIST_DIR=`realpath $DIST_DIR`
TF_DIR=`realpath $1`
BRANCH=$2

if [ ! -d $TF_DIR ]; then
	log "First param must be tensorflow repo path"
	exit 1
fi

if [ -e $BRANCH ]; then
	log "Second param must be a branch/tag"
	exit 1
fi

cd $DIST_DIR
log "clean local dist"
if [ -d include ]; then
	rm -rf include
fi
if [ -d libs ]; then
	rm -rf libs
fi
mkdir -p libs

cd $TF_DIR
log "Switching to $BRANCH"
git checkout $BRANCH
git checkout .
git apply $DIST_DIR/patch/000-add-apis.patch

log "bazel clean"
bazel clean

for i in ${!ARCHS[@]}; do
	buildArch ${ARCHS[$i]} ${ABIS[$i]}
done

collectHeaders

bazel build -c opt --fat_apk_cpu=x86_64,arm64-v8a --host_crosstool_top=@bazel_tools//tools/cpp:toolchain //tensorflow/lite/java:tensorflow-lite --copt -Os --copt -DTFLITE_GPU_BINARY_RELEASE --copt -s --strip always
chmod +w $DIST_DIR/tensorflow-lite.aar
cp $TF_DIR/bazel-bin/tensorflow/lite/java/tensorflow-lite.aar $DIST_DIR

cd $DIST_DIR
rm -rf $DIST_DIR/aar
unzip $DIST_DIR/tensorflow-lite.aar -d $DIST_DIR/aar

for i in ${!ARCHS[@]}; do
	mv $DIST_DIR/aar/jni/${ABIS[$i]}/libtensorflowlite_jni.so $DIST_DIR/libs/${ABIS[$i]}
done

rm -rf aar

# build-android.sh ~/gits/tensorflow tags/v2.5.0