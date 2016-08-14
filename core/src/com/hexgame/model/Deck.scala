package com.hexgame.model
import com.badlogic.gdx.graphics.Texture
import com.badlogic.gdx.graphics.g2d.Sprite
import com.hexgame.helper.HexHelper
import com.hexgame.model.Side

class Deck (val text: Texture=HexHelper.getNextTexture()) extends Sprite(text) {
  var side: Side = null
  next()

  def next() {
    this.side = Side.getRandomSide()
    this.setTexture(new Texture(side.getTexture()))
  }
}