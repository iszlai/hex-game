import com.badlogic.gdx.graphics.Texture
import com.badlogic.gdx.graphics.g2d.Sprite
import com.hexgame.model.Sides
import com.hexgame.utils.Utils

class Deck extends Sprite {
  var side: Sides.Side = null

  def this() {
    this()
    `super`(getNextTexture)
    next
  }

  private def getNextTexture: Texture = {
    return new Texture(Utils.randomEnum(classOf[Sides]).textureFile)
  }

  def next {
    this.side = Utils.randomEnum(classOf[Sides])
    this.setTexture(new Texture(side.textureFile))
  }
}