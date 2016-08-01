package com.hexgame.screen

import com.badlogic.gdx.{Gdx, Screen}
import com.badlogic.gdx.graphics.{GL20, Texture}
import com.badlogic.gdx.graphics.g2d.{SpriteBatch, Sprite}

/**
  * Created by leheli on 2016.08.01..
  */
class StarsScreen extends Screen {
  private val currentLevel: Int = 0
  private val app: Hex = null
  private[screens] var star: Sprite = null
  private[screens] var batch: SpriteBatch = null
  private[screens] var starTexture: Texture = null

  def this (app: Hex, i: Int) {
  this ()
  this.app = app
  this.currentLevel = i
  starTexture = new Texture ("star.png")
  star = new Sprite (starTexture)
  star.setX (Gdx.graphics.getWidth / 2)
  star.setY (Gdx.graphics.getHeight / 2)
  batch = new SpriteBatch
}

  def show {
}

  def render (delta: Float) {
  Gdx.gl.glClearColor (0.81f, 0.85f, 0.86f, 1)
  Gdx.gl.glClear (GL20.GL_COLOR_BUFFER_BIT)
  batch.begin
  star.draw (batch)
  batch.end
  app.batch.begin
  app.font.draw (app.batch, "Current Level: " + this.currentLevel, Gdx.graphics.getWidth / 2 - 100, Gdx.graphics.getHeight / 2)
  app.batch.end
  update (delta)
}

  private def update (delta: Float) {
  if (Gdx.input.justTouched) {
  val x: Float = Gdx.input.getX
  val y: Float = Gdx.graphics.getHeight - Gdx.input.getY
  if (star.getBoundingRectangle.contains (x, y) ) {
  this.app.setScreen (new LevelScreen (app, currentLevel) )
}
}
}

  def resize (width: Int, height: Int) {
}

  def pause {
}

  def resume {
}

  def hide {
}

  def dispose {
  batch.dispose
  star.getTexture.dispose
}
}