package com.hexgame

import com.badlogic.gdx.Game
import com.badlogic.gdx.assets.AssetManager
import com.badlogic.gdx.graphics.{Color, OrthographicCamera}
import com.badlogic.gdx.graphics.g2d.{BitmapFont, SpriteBatch}
import com.badlogic.gdx.scenes.scene2d.Stage
import com.hexgame.UtilsT._
import com.hexgame.screens.SplashScreen

/**
  * Created by leheli on 2016.08.01..
  */
object Hex {
  val V_WIDTH: Float = 480
  val V_HEIGHT: Float = 289
}

class Hex extends Game {
  private var stage: Stage = null
  var batch: SpriteBatch = null
  var font: BitmapFont = null
  var camera: OrthographicCamera = null
  var assets: AssetManager = null

  def create {
    assets = new AssetManager
    camera = new OrthographicCamera
    camera.setToOrtho(false, 1080, 1794)
    batch = new SpriteBatch
    font = new BitmapFont
    font.setColor(Color.BLACK)
    font.getData.setScale(8f)
    this.setScreen(new SplashScreen(this))
  }

  override def render {
    super.render
  }

  override def dispose {
    batch.dispose
    font.dispose
    assets.dispose
    this.getScreen.dispose
  }

  def test {
    if (isReady) {
      System.out.print("Should compile!")
    }
  }
}