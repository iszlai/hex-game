package com.hexgame.screen

import com.badlogic.gdx.math.Interpolation
import com.badlogic.gdx.scenes.scene2d.{Action, Stage}
import com.badlogic.gdx.utils.viewport.FitViewport
import com.badlogic.gdx.{Gdx, Screen}
import com.badlogic.gdx.graphics.{GL20, Texture}
import com.badlogic.gdx.scenes.scene2d.actions.Actions._
import com.badlogic.gdx.scenes.scene2d.ui.Image
import com.hexgame.Hex

/**
  * Created by leheli on 2016.08.01..
  */
class SplashScreen(app: Hex) extends Screen {
  private var splashImage: Image = null

  val stage = new Stage (new FitViewport (Hex.V_WIDTH, Hex.V_HEIGHT, app.camera) )
  Gdx.input.setInputProcessor (stage)
  val splashTex: Texture = new Texture ("BLUE.png")
  splashImage = new Image (splashTex)
  splashImage.setOrigin (splashImage.getWidth / 2, splashImage.getHeight / 2)
  stage.addActor (splashImage)

  def show {
  splashImage.setPosition (stage.getWidth / 2 - 16, stage.getHeight / 2 + 16)
  splashImage.addAction (sequence (alpha (0f), scaleTo (0.1f, 0.1f), parallel (fadeIn (2f, Interpolation.pow2), scaleTo (2f, 2f, 2.5f, Interpolation.pow5), moveTo (stage.getWidth / 2 - 16, stage.getHeight / 2 - 16, 2f, Interpolation.swing) ), new Action () {
  def act (delta: Float): Boolean = {
  app.setScreen (new LevelScreen (app, 0) )
  return true
}
}) )
}

  def render (delta: Float) {
  Gdx.gl.glClearColor (0.81f, 0.85f, 0.86f, 1)
  Gdx.gl.glClear (GL20.GL_COLOR_BUFFER_BIT)
  stage.draw
  update (delta)
  app.batch.begin
  app.font.draw (app.batch, "SpashScreen", stage.getWidth / 2, stage.getHeight / 2)
  app.batch.end
}

  private def update (delta: Float) {
  stage.act (delta)
}

  def resize (width: Int, height: Int) {
  stage.getViewport.update (width, height, false)
}

  def pause {
}

  def resume {
}

  def hide {
}

  def dispose {
  stage.dispose
}
}

