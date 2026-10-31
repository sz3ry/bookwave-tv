package com.sz3ry.bookwavetv

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    // Back with nothing left to pop in Flutter (the player screen) acts like
    // Home: the activity is not finished, so the book keeps playing and the
    // player is still there when the app is opened again.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }
}
